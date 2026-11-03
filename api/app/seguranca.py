"""Autenticação, autorização (RBAC) e proteção de dados na aplicação."""
import hashlib
import ipaddress
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import jwt
import pyotp
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
from cryptography.fernet import Fernet
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import config
from .db import transacao

_hasher = PasswordHasher()           # Argon2id, parâmetros padrão da biblioteca
_bearer = HTTPBearer(auto_error=False)
# hash válido de referência: login de usuário inexistente gasta o mesmo
# tempo que um login real (não revela quais logins existem)
_HASH_FICTICIO = _hasher.hash("usuario-inexistente")


# ----------------------------------------------------------------- senhas
def gerar_hash_senha(senha: str) -> str:
    return _hasher.hash(senha)


def conferir_senha(hash_salvo: str, senha: str) -> bool:
    try:
        return _hasher.verify(hash_salvo, senha)
    except (VerifyMismatchError, InvalidHashError):
        return False


# ------------------------------------------------- cifra de segredos (MFA)
def cifrar(texto: str) -> bytes:
    return Fernet(config().chave_cifra.encode()).encrypt(texto.encode())


def decifrar(dados: bytes) -> str:
    return Fernet(config().chave_cifra.encode()).decrypt(bytes(dados)).decode()


def conferir_totp(segredo_cifrado: bytes | None, codigo: str | None) -> bool:
    if not segredo_cifrado or not codigo:
        return False
    return pyotp.TOTP(decifrar(segredo_cifrado)).verify(codigo, valid_window=1)


# ----------------------------------------------------------------- tokens
def emitir_access_token(id_usuario: int, login: str) -> str:
    agora = datetime.now(timezone.utc)
    corpo = {"sub": str(id_usuario), "login": login, "iat": agora,
             "exp": agora + timedelta(minutes=config().access_ttl_min), "typ": "access"}
    return jwt.encode(corpo, config().jwt_segredo, algorithm="HS256")


def novo_refresh_token() -> tuple[str, str]:
    """Devolve (token para o cliente, hash para o banco)."""
    token = secrets.token_urlsafe(48)
    return token, hashlib.sha256(token.encode()).hexdigest()


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


# ---------------------------------------------------------- usuário atual
@dataclass
class Usuario:
    id_usuario: int
    login: str
    perfis: set[str]
    permissoes: set[tuple[str, str]]
    ip: str | None

    def pode(self, recurso: str, acao: str) -> bool:
        return (recurso, acao) in self.permissoes


def ip_do_cliente(request: Request) -> str | None:
    """IP de origem validado (vai para uma coluna INET do log)."""
    host = request.client.host if request.client else None
    try:
        return str(ipaddress.ip_address(host)) if host else None
    except ValueError:
        return None


def usuario_atual(request: Request,
                  cred: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> Usuario:
    erro = HTTPException(status.HTTP_401_UNAUTHORIZED, "Token ausente, inválido ou expirado",
                         headers={"WWW-Authenticate": "Bearer"})
    if cred is None:
        raise erro
    try:
        corpo = jwt.decode(cred.credentials, config().jwt_segredo, algorithms=["HS256"],
                           options={"require": ["exp", "sub"]})
    except jwt.PyJWTError:
        raise erro
    if corpo.get("typ") != "access":
        raise erro
    id_usuario = int(corpo["sub"])
    with transacao() as conn:
        linhas = conn.execute(
            "SELECT login, perfil, recurso, acao FROM vw_permissoes_usuario WHERE id_usuario = %s",
            (id_usuario,)).fetchall()
    if not linhas:            # usuário desativado ou sem perfil
        raise erro
    return Usuario(id_usuario=id_usuario, login=linhas[0]["login"],
                   perfis={l["perfil"] for l in linhas},
                   permissoes={(l["recurso"], l["acao"]) for l in linhas},
                   ip=ip_do_cliente(request))


def exige(recurso: str, acao: str):
    """Dependência FastAPI: bloqueia (403) e registra a tentativa no log."""
    def verificar(usuario: Usuario = Depends(usuario_atual)) -> Usuario:
        if not usuario.pode(recurso, acao):
            with transacao() as conn:
                conn.execute("SELECT fn_registrar_acesso(%s, 'ACESSO_NEGADO', %s, NULL, %s, %s)",
                             (usuario.id_usuario, recurso, usuario.ip, f"tentou {acao}"))
            raise HTTPException(status.HTTP_403_FORBIDDEN,
                                f"Seu perfil não tem a permissão {recurso}:{acao}")
        return usuario
    return verificar


# ------------------------------------------------------ minimização na tela
def mascarar_cpf(cpf: str | None) -> str | None:
    if not cpf:
        return None
    return f"***.{cpf[3:6]}.{cpf[6:9]}-**"


def mascarar_telefone(tel: str | None) -> str | None:
    if not tel:
        return None
    return "*" * (len(tel) - 4) + tel[-4:]
