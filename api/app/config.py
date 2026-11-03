"""Configuração lida do ambiente.

Nenhuma credencial fica no código. Em produção as variáveis são
injetadas pelo cofre de segredos (ex.: AWS Secrets Manager, Azure Key
Vault ou HashiCorp Vault); no protótipo, pelo arquivo .env do Docker
Compose, que não vai para o Git (.gitignore).
"""
import os
from dataclasses import dataclass, field


def _obrigatoria(nome: str) -> str:
    valor = os.environ.get(nome)
    if not valor:
        raise RuntimeError(f"Variável de ambiente obrigatória ausente: {nome}")
    return valor


@dataclass(frozen=True)
class Config:
    database_url: str = field(default_factory=lambda: _obrigatoria("SVP_DATABASE_URL"))
    dw_database_url: str = field(default_factory=lambda: _obrigatoria("SVP_DW_DATABASE_URL"))
    jwt_segredo: str = field(default_factory=lambda: _obrigatoria("SVP_JWT_SECRET"))
    chave_cifra: str = field(default_factory=lambda: _obrigatoria("SVP_CHAVE_CIFRA"))
    url_publica: str = field(default_factory=lambda: os.environ.get("SVP_URL_PUBLICA", "http://api:8000"))
    pasta_documentos: str = field(default_factory=lambda: os.environ.get("SVP_PASTA_DOCUMENTOS", "/data/documentos"))
    access_ttl_min: int = int(os.environ.get("SVP_ACCESS_TTL_MIN", "15"))
    refresh_ttl_horas: int = int(os.environ.get("SVP_REFRESH_TTL_HORAS", "12"))
    max_falhas_login: int = 5
    bloqueio_min: int = 15
    janela_webhook_s: int = 300          # assinatura vale por 5 minutos (anti-replay)
    max_corpo_webhook: int = 10 * 1024 * 1024


def obter_segredo(referencia: str) -> str:
    """Resolve um segredo pela referência guardada no banco.

    'svp/laboratorio/1/webhook' -> variável SVP_SECRET__LABORATORIO_1_WEBHOOK.
    Em produção esta função consulta o cofre; a assinatura não muda.
    """
    partes = referencia.removeprefix("svp/").replace("-", "_").split("/")
    return _obrigatoria("SVP_SECRET__" + "_".join(partes).upper())


_config: Config | None = None


def config() -> Config:
    global _config
    if _config is None:
        _config = Config()
    return _config
