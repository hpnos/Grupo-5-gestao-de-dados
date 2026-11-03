"""Login com bloqueio por tentativas, MFA opcional e sessões revogáveis."""
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field

from ..config import config
from ..db import transacao
from ..seguranca import (_HASH_FICTICIO, Usuario, conferir_senha, conferir_totp,
                         emitir_access_token, hash_token, ip_do_cliente,
                         novo_refresh_token, usuario_atual)

router = APIRouter(prefix="/auth", tags=["autenticação"])


class Login(BaseModel):
    login: str = Field(min_length=3, max_length=50)
    senha: str = Field(min_length=1, max_length=200)
    codigo_mfa: str | None = Field(default=None, pattern=r"^\d{6}$")


class Refresh(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=200)


def _tokens(conn, id_usuario: int, login: str, ip: str | None) -> dict:
    token, h = novo_refresh_token()
    conn.execute(
        "INSERT INTO sessao (id_usuario, refresh_hash, expira_em, ip_origem) VALUES (%s, %s, %s, %s)",
        (id_usuario, h, datetime.now(timezone.utc) + timedelta(hours=config().refresh_ttl_horas), ip))
    return {"access_token": emitir_access_token(id_usuario, login), "token_type": "bearer",
            "expires_in": config().access_ttl_min * 60, "refresh_token": token}


@router.post("/login")
def login(dados: Login, request: Request):
    """As falhas são gravadas ANTES de responder: a transação faz commit e
    só depois o erro é devolvido (senão o rollback apagaria o registro)."""
    ip = ip_do_cliente(request)
    erro: HTTPException | None = None
    with transacao() as conn:
        u = conn.execute(
            """SELECT id_usuario, login, senha_hash, ativo, mfa_ativo, mfa_segredo_cif,
                      falhas_login, bloqueado_ate
               FROM usuario WHERE login = %s FOR UPDATE""", (dados.login,)).fetchone()

        if u is None:
            conferir_senha(_HASH_FICTICIO, dados.senha)        # mesmo custo de tempo
            conn.execute("SELECT fn_registrar_acesso(NULL, 'LOGIN_FALHA', 'usuario', NULL, %s, %s)",
                         (ip, "login inexistente"))
            erro = HTTPException(status.HTTP_401_UNAUTHORIZED, "Login ou senha inválidos")

        elif u["bloqueado_ate"] and u["bloqueado_ate"] > datetime.now(timezone.utc):
            conn.execute("SELECT fn_registrar_acesso(%s, 'LOGIN_FALHA', 'usuario', %s, %s, %s)",
                         (u["id_usuario"], u["id_usuario"], ip, "usuário bloqueado"))
            erro = HTTPException(status.HTTP_423_LOCKED,
                                 "Usuário bloqueado temporariamente por excesso de tentativas")
        else:
            senha_ok = conferir_senha(u["senha_hash"], dados.senha)
            mfa_ok = (not u["mfa_ativo"]) or conferir_totp(u["mfa_segredo_cif"], dados.codigo_mfa)

            if senha_ok and mfa_ok and u["ativo"]:
                conn.execute("""UPDATE usuario SET falhas_login = 0, bloqueado_ate = NULL,
                                       ultimo_acesso = now() WHERE id_usuario = %s""", (u["id_usuario"],))
                conn.execute("SELECT fn_registrar_acesso(%s, 'LOGIN', 'usuario', %s, %s, NULL)",
                             (u["id_usuario"], u["id_usuario"], ip))
                return _tokens(conn, u["id_usuario"], u["login"], ip)

            falhas = u["falhas_login"] + 1
            bloqueia = falhas >= config().max_falhas_login
            conn.execute("UPDATE usuario SET falhas_login = %s, bloqueado_ate = %s WHERE id_usuario = %s",
                         (0 if bloqueia else falhas,
                          datetime.now(timezone.utc) + timedelta(minutes=config().bloqueio_min) if bloqueia else None,
                          u["id_usuario"]))
            motivo = ("usuário inativo" if not u["ativo"] else "senha incorreta" if not senha_ok
                      else "código MFA inválido")
            conn.execute("SELECT fn_registrar_acesso(%s, 'LOGIN_FALHA', 'usuario', %s, %s, %s)",
                         (u["id_usuario"], u["id_usuario"], ip, motivo + (" — bloqueado" if bloqueia else "")))
            erro = HTTPException(status.HTTP_401_UNAUTHORIZED, "Login ou senha inválidos")
    raise erro


@router.post("/refresh")
def refresh(dados: Refresh, request: Request):
    with transacao() as conn:
        s = conn.execute(
            """SELECT s.id_sessao, u.id_usuario, u.login FROM sessao s
               JOIN usuario u ON u.id_usuario = s.id_usuario
               WHERE s.refresh_hash = %s AND s.revogada_em IS NULL AND s.expira_em > now() AND u.ativo
               FOR UPDATE OF s""", (hash_token(dados.refresh_token),)).fetchone()
        if s is None:
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Sessão inválida ou expirada")
        # rotação: o refresh token usado deixa de valer
        conn.execute("UPDATE sessao SET revogada_em = now() WHERE id_sessao = %s", (s["id_sessao"],))
        return _tokens(conn, s["id_usuario"], s["login"], ip_do_cliente(request))


@router.post("/logout", status_code=204)
def logout(dados: Refresh, usuario: Usuario = Depends(usuario_atual)):
    with transacao(usuario.id_usuario) as conn:
        conn.execute("""UPDATE sessao SET revogada_em = now()
                        WHERE refresh_hash = %s AND id_usuario = %s AND revogada_em IS NULL""",
                     (hash_token(dados.refresh_token), usuario.id_usuario))
        conn.execute("SELECT fn_registrar_acesso(%s, 'LOGOUT', 'usuario', %s, %s, NULL)",
                     (usuario.id_usuario, usuario.id_usuario, usuario.ip))
