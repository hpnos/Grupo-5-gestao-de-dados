"""Repositório de arquivos (laudos, exames, imagens).

O banco guarda só o caminho e o SHA-256 (tabela documento); o arquivo
fica aqui. No protótipo é uma pasta (volume Docker); em produção, um
bucket de object storage privado com criptografia no servidor e
versionamento (ex.: Amazon S3 em sa-east-1). A interface é a mesma.

Os arquivos são endereçados pelo próprio hash: o mesmo laudo recebido
duas vezes vira o mesmo arquivo, e qualquer alteração no conteúdo é
detectada na leitura.
"""
import hashlib
import os
from pathlib import Path

from .config import config


def sha256(dados: bytes) -> str:
    return hashlib.sha256(dados).hexdigest()


def caminho_para(hash_hex: str) -> str:
    return f"documentos/{hash_hex[:2]}/{hash_hex[2:4]}/{hash_hex}"


def gravar(dados: bytes) -> tuple[str, str]:
    """Grava de forma atômica e devolve (caminho, sha256)."""
    h = sha256(dados)
    destino = Path(config().pasta_documentos) / caminho_para(h)
    if not destino.exists():
        destino.parent.mkdir(parents=True, exist_ok=True)
        temporario = destino.with_suffix(".tmp")
        with open(temporario, "wb") as f:
            f.write(dados)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temporario, destino)          # ou grava inteiro, ou não grava
    return caminho_para(h), h


def ler(caminho: str, hash_esperado: str) -> bytes:
    dados = (Path(config().pasta_documentos) / caminho).read_bytes()
    if sha256(dados) != hash_esperado:
        raise ValueError("Arquivo corrompido ou alterado: hash não confere")
    return dados
