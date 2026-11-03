"""Diagramas como código: gera os SVG/PNG do repositório.

    python diagrams/gerar_diagramas.py

Saída: diagrams/arquitetura-final.{svg,png} e
       diagrams/fluxo-integracao-laboratorio.{svg,png}
Com --jsx, grava também a versão para o documento consolidado.
"""
import sys
from pathlib import Path

PASTA = Path(__file__).resolve().parent

# tokens de cor (documento) -> cores do SVG estático (tema claro)
CORES = {
    "ink": ("var(--cds-text-primary)", "#1f2328"),
    "quiet": ("var(--cds-text-secondary)", "#57606a"),
    "edge": ("var(--cds-chart-axis)", "#8c959f"),
    "grid": ("var(--cds-chart-grid)", "#d0d7de"),
    "tint": ("var(--cds-chart-reference-tint)", "#f6f8fa"),
    "INT": ("var(--cds-chart-categorical-1)", "#2f6feb"),
    "MOD": ("var(--cds-chart-categorical-2)", "#8250df"),
    "STO": ("var(--cds-chart-categorical-3)", "#1a7f37"),
    "SEC": ("var(--cds-chart-categorical-4)", "#cf222e"),
    "ARQ": ("var(--cds-chart-categorical-5)", "#bf8700"),
}


class Desenho:
    def __init__(self, nome: str, altura: int, titulo: str):
        self.nome, self.altura, self.titulo = nome, altura, titulo
        self.partes: list[tuple] = []          # (tipo, dados)

    # ------------------------------------------------------------ primitivas
    def texto(self, tid, x, y, s, tam=11.5, peso=None, cor="ink", ancora=None):
        self.partes.append(("t", dict(id=tid, x=x, y=y, s=s, tam=tam, peso=peso, cor=cor, ancora=ancora)))

    def ret(self, x, y, w, h, cor="edge", preench=None, opac=None, larg=1.25, rx=8, tracejado=False):
        self.partes.append(("r", dict(x=x, y=y, w=w, h=h, cor=cor, preench=preench, opac=opac, larg=larg,
                                      rx=rx, tracejado=tracejado)))

    def linha(self, pontos, seta=True, tracejado=False, cor="edge"):
        self.partes.append(("l", dict(p=pontos, seta=seta, tracejado=tracejado, cor=cor)))

    def grupo(self, ancora):
        self.partes.append(("g", ancora))

    def fim_grupo(self):
        self.partes.append(("/g", None))

    # ------------------------------------------------------------ compostos
    def chip(self, tid, x, y, sigla):
        self.ret(x, y, 36, 18, cor=sigla, preench=sigla, opac=0.15, larg=1, rx=9)
        self.texto(tid, x + 18, y + 13, sigla, tam=10.5, peso=600, ancora="middle")

    def caixa(self, gid, x, y, w, nome, linhas=(), chips=(), destaque=False):
        h = (68 if chips else 40) + 16 * len(linhas) if linhas else (68 if chips else 44)
        self.grupo(gid)
        if destaque:
            self.ret(x, y, w, h, cor="INT", preench="INT", opac=0.08, larg=2)
        else:
            self.ret(x, y, w, h)
        self.texto(f"{gid}-nome", x + 12, y + 24, nome, tam=13, peso=600)
        for i, sigla in enumerate(chips):
            self.chip(f"{gid}-{sigla.lower()}", x + 12 + i * 42, y + 34, sigla)
        base = y + (68 if chips else 40)
        for i, l in enumerate(linhas):
            self.texto(f"{gid}-l{i + 1}", x + 12, base + 16 * i, l, cor="quiet")
        self.fim_grupo()
        return h

    # ------------------------------------------------------------ saída
    def _cor(self, chave, jsx):
        return CORES[chave][0 if jsx else 1]

    def render(self, jsx: bool) -> str:
        q = "'" if jsx else '"'
        a = (lambda k, v: f" {k}={q}{v}{q}")
        nomes = {"stroke-width": "strokeWidth", "text-anchor": "textAnchor", "font-size": "fontSize",
                 "font-weight": "fontWeight", "fill-opacity": "fillOpacity", "marker-end": "markerEnd",
                 "stroke-dasharray": "strokeDasharray", "font-family": "fontFamily"}
        n = (lambda k: nomes.get(k, k) if jsx else k)
        mid = f"{self.nome}-arrow"
        out = [f"<svg viewBox={q}0 0 760 {self.altura}{q}" + (" xmlns=\"http://www.w3.org/2000/svg\"" if not jsx else "")
               + a("role", "img") + a("aria-label", self.titulo) + a(n("font-size"), 12)
               + ("" if jsx else a("font-family", "Inter, Segoe UI, Helvetica, Arial, sans-serif")) + ">"]
        out.append(f"<defs><marker id={q}{mid}{q} viewBox={q}0 0 10 10{q} refX={q}9{q} refY={q}5{q} "
                   f"markerWidth={q}6{q} markerHeight={q}6{q} orient={q}auto-start-reverse{q}>"
                   f"<path d={q}M0 0L10 5L0 10z{q} fill={q}{self._cor('edge', jsx)}{q}/></marker></defs>")
        if not jsx:
            out.append(f'<rect width="760" height="{self.altura}" fill="#ffffff"/>')
        for tipo, d in self.partes:
            if tipo == "g":
                out.append(f"<g data-claude-anchor={q}{d}{q}>" if jsx else f'<g id="{d}">')
            elif tipo == "/g":
                out.append("</g>")
            elif tipo == "r":
                s = (f"<rect{a('x', d['x'])}{a('y', d['y'])}{a('width', d['w'])}{a('height', d['h'])}{a('rx', d['rx'])}"
                     f"{a('fill', self._cor(d['preench'], jsx) if d['preench'] else 'none')}"
                     f"{a(n('fill-opacity'), d['opac']) if d['opac'] else ''}"
                     f"{a('stroke', self._cor(d['cor'], jsx))}{a(n('stroke-width'), d['larg'])}"
                     f"{a(n('stroke-dasharray'), '4 4') if d['tracejado'] else ''}/>")
                out.append(s)
            elif tipo == "l":
                caminho = "M" + " L".join(f"{x} {y}" for x, y in d["p"])
                out.append(f"<path{a('d', caminho)}{a('fill', 'none')}{a('stroke', self._cor(d['cor'], jsx))}"
                           f"{a(n('stroke-width'), 1.25)}{a(n('stroke-dasharray'), '5 4') if d['tracejado'] else ''}"
                           f"{a(n('marker-end'), f'url(#{mid})') if d['seta'] else ''}/>")
            elif tipo == "t":
                s = d["s"].replace("&", "e").replace("<", "‹").replace(">", "›")
                attrs = (a("data-claude-text-id", d["id"]) if jsx else "") + a("x", d["x"]) + a("y", d["y"]) \
                    + a(n("font-size"), d["tam"]) + (a(n("font-weight"), d["peso"]) if d["peso"] else "") \
                    + (a(n("text-anchor"), d["ancora"]) if d["ancora"] else "") + a("fill", self._cor(d["cor"], jsx))
                out.append(f"<text{attrs}>{s}</text>")
        out.append("</svg>")
        return "".join(out)


# =================================================================== desenho 1
def arquitetura() -> Desenho:
    d = Desenho("arq", 776, "Cada dado fica onde é mais útil e mais protegido")
    d.texto("title", 24, 30, "Cada dado fica onde é mais útil e mais protegido", tam=15, peso=600)
    d.texto("subtitle", 24, 50, "Arquitetura de dados do SVP; as siglas marcam onde está cada entrega", cor="quiet")

    c1, c2, c3, c4, w = 24, 202, 380, 558, 154

    d.texto("lane-usuarios", 24, 80, "USUÁRIOS E PARCEIROS", tam=10.5, peso=600, cor="quiet")
    d.caixa("equipe", c1, 90, w, "Equipe da clínica", ["navegador e app"])
    d.grupo("parceiros")
    d.ret(c2, 90, 332, 80)
    d.texto("parceiros-nome", c2 + 12, 112, "Parceiros externos", tam=13, peso=600)
    d.chip("parceiros-int", c2 + 286, 98, "INT")
    d.ret(c2 + 12, 124, 148, 34, rx=6)
    d.texto("lab", c2 + 86, 145, "Laboratório", tam=12.5, ancora="middle")
    d.ret(c2 + 172, 124, 148, 34, rx=6)
    d.texto("pagamento", c2 + 246, 145, "Pagamento · NFS-e", tam=12.5, ancora="middle")
    d.fim_grupo()
    d.caixa("diretoria", c4, 90, w, "Diretoria", ["painel de indicadores"])

    # fronteira TLS
    d.grupo("fronteira-tls")
    d.linha([(24, 206), (712, 206)], seta=False, tracejado=True, cor="SEC")
    d.texto("tls", 486, 199, "fronteira HTTPS/TLS e firewall", tam=11.5, cor="quiet")
    d.chip("tls-sec", 676, 186, "SEC")
    d.fim_grupo()

    d.texto("lane-aplicacao", 24, 246, "APLICAÇÃO", tam=10.5, peso=600, cor="quiet")
    d.caixa("api", c1, 256, 332, "API SVP (FastAPI)",
            ["login Argon2id + MFA, sessão revogável",
             "RBAC: 7 perfis, permissão por recurso e ação",
             "registra leituras, alterações e acessos negados"], ["SEC", "INT"], destaque=True)
    d.caixa("worker", c3, 256, w, "Worker (outbox)",
            ["fila no PostgreSQL", "retentativa 30 s a 1 h", "mesma chave no reenvio"], ["INT"])
    d.caixa("cofre", c4, 256, w, "Cofre de segredos",
            ["senhas dos papéis", "tokens e chaves", "nada no código"], ["SEC"])

    d.texto("lane-dados", 24, 396, "DADOS", tam=10.5, peso=600, cor="quiet")
    d.caixa("postgres", c1, 406, w, "PostgreSQL 16", ["46 tabelas, 3FN", "log particionado", "regras no banco"],
            ["MOD", "STO"])
    d.caixa("objetos", c2, 406, w, "Object storage", ["laudos e imagens", "cifrado, versionado", "nome = SHA-256"],
            ["STO", "SEC"])
    d.caixa("replica", c3, 406, w, "Réplica (leitura)", ["outra zona", "assume se o primário", "cair; fonte do ETL"],
            ["STO"])

    d.texto("lane-analitico", c2, 576, "ANÁLISE E CÓPIAS", tam=10.5, peso=600, cor="quiet")
    d.caixa("backup", c1, 586, w, "Backups", ["banco: PITR + diário", "arquivos: versões"], ["STO", "SEC"])
    d.caixa("etl", c3, 586, w, "ETL noturno", ["ids com HMAC", "janela de 90 dias"], ["INT", "SEC"])
    d.caixa("dw", c4, 586, w, "Data warehouse", ["modelo estrela", "sem dado do tutor"], ["MOD", "STO"])

    d.grupo("conexoes")
    d.linha([(101, 146), (101, 256)])                                  # equipe -> api
    d.linha([(300, 170), (300, 256)])                                  # parceiros -> api (webhooks)
    d.linha([(457, 256), (457, 170)])                                  # worker -> parceiros (pedidos)
    d.linha([(534, 314), (558, 314)][::-1], tracejado=True)            # cofre -> worker
    d.linha([(101, 372), (101, 406)])                                  # api -> postgres
    d.linha([(279, 372), (279, 406)])                                  # api -> objetos
    d.linha([(140, 522), (140, 548), (410, 548), (410, 522)])          # replicação
    d.linha([(70, 522), (70, 586)])                                    # backup
    d.linha([(500, 522), (500, 586)])                                  # réplica -> etl
    d.linha([(534, 636), (558, 636)])                                  # etl -> dw
    d.linha([(712, 636), (736, 636), (736, 120), (712, 120)])           # dw -> diretoria
    d.fim_grupo()
    d.texto("rot-webhooks", 306, 240, "webhooks", tam=11, cor="quiet")
    d.texto("rot-pedidos", 463, 240, "pedidos", tam=11, cor="quiet")
    d.texto("rot-replicacao", 275, 542, "replicação contínua", tam=11, cor="quiet", ancora="middle")

    # legenda
    d.grupo("legenda")
    d.chip("leg-arq", 24, 706, "ARQ")
    d.texto("leg-arq-t", 66, 719, "Data Architecture: o desenho todo, com camadas, componentes e fluxos", tam=11.5)
    d.chip("leg-mod", 24, 734, "MOD")
    d.texto("leg-mod-t", 66, 747, "Modeling", tam=11.5)
    d.chip("leg-sto", 140, 734, "STO")
    d.texto("leg-sto-t", 182, 747, "Storage", tam=11.5)
    d.chip("leg-sec", 252, 734, "SEC")
    d.texto("leg-sec-t", 294, 747, "Security", tam=11.5)
    d.chip("leg-int", 368, 734, "INT")
    d.texto("leg-int-t", 410, 747, "Integration", tam=11.5)
    d.fim_grupo()
    return d


# =================================================================== desenho 2
def fluxo() -> Desenho:
    d = Desenho("seq", 660, "O pedido nasce no mesmo commit e viaja sempre com a mesma chave")
    d.texto("title", 24, 30, "O pedido nasce no mesmo commit e viaja sempre com a mesma chave", tam=15, peso=600)
    xs = {"api": 96, "pg": 246, "worker": 396, "lab": 550, "obj": 680}
    nomes = {"api": "API SVP", "pg": "PostgreSQL", "worker": "Worker", "lab": "Laboratório", "obj": "Object storage"}
    larg = {"api": 120, "pg": 120, "worker": 120, "lab": 120, "obj": 110}
    for k, x in xs.items():
        d.grupo(f"vida-{k}")
        d.ret(x - larg[k] / 2, 56, larg[k], 32, cor="INT" if k == "api" else "edge",
              preench="INT" if k == "api" else None, opac=0.08 if k == "api" else None, larg=1.5 if k == "api" else 1.25)
        d.texto(f"cab-{k}", x, 77, nomes[k], tam=12.5, peso=600, ancora="middle")
        d.linha([(x, 88), (x, 640)], seta=False, tracejado=True, cor="grid")
        d.fim_grupo()

    def msg(mid, y, de, para, rotulo, resposta=False):
        x1, x2 = xs[de], xs[para]
        d.linha([(x1, y), (x2 + (-4 if x2 > x1 else 4), y)], tracejado=resposta)
        xt = min(x1, x2) + 8
        d.texto(mid, xt, y - 7, rotulo, tam=11.5)

    def nota(nid, x, y, linhas, cor="edge"):
        h = 12 + 15 * len(linhas)
        d.grupo(nid)
        d.ret(24, y, 168, h, cor=cor, preench="tint", larg=1, rx=6)
        for i, l in enumerate(linhas):
            d.texto(f"{nid}-{i + 1}", 32, y + 19 + 15 * i, l, tam=11)
        d.fim_grupo()
        return y + h

    nota("passo1", xs["api"], 98, ["1  confere o perfil, se o", "pedido está COLETADO e", "se há consentimento"])
    msg("passo2", 180, "api", "pg", "2  INSERT no outbox")
    msg("passo3", 220, "worker", "pg", "3  pega lote (lease)")
    msg("passo4", 260, "worker", "lab", "4  POST /pedidos + chave")
    msg("passo5", 300, "lab", "worker", "5  201 + protocolo", resposta=True)
    d.grupo("erro")
    d.ret(404, 310, 138, 40, cor="SEC", preench="tint", larg=1, rx=6)
    d.texto("erro-1", 412, 326, "503 ou timeout: ERRO,", tam=11, cor="ink")
    d.texto("erro-2", 412, 341, "tenta de novo depois", tam=11, cor="ink")
    d.fim_grupo()
    msg("passo6", 380, "worker", "pg", "6  ENVIADO + protocolo")
    msg("passo7", 422, "lab", "api", "7  webhook: HMAC + timestamp + chave")
    nota("passo8", xs["api"], 434, ["8  confere assinatura,", "chave, formato,", "protocolo, versão", "e SHA-256 do laudo"])
    msg("passo9", 530, "api", "obj", "9  grava o laudo; o nome do arquivo é o SHA-256")
    msg("passo10", 570, "api", "pg", "10  CONCLUIDO + inbox")
    msg("passo11", 610, "api", "lab", "11  200: processado, duplicado ou versão antiga", resposta=True)
    return d


def main() -> None:
    import cairosvg
    for desenho, arquivo in ((arquitetura(), "arquitetura-final"), (fluxo(), "fluxo-integracao-laboratorio")):
        svg = desenho.render(jsx=False)
        (PASTA / f"{arquivo}.svg").write_text(svg, encoding="utf-8")
        cairosvg.svg2png(bytestring=svg.encode(), write_to=str(PASTA / f"{arquivo}.png"), output_width=1520)
        if "--jsx" in sys.argv:
            destino = Path(sys.argv[sys.argv.index("--jsx") + 1]) / f"{arquivo}.jsx"
            destino.write_text("export default () => " + desenho.render(jsx=True) + ";", encoding="utf-8")
        print("ok", arquivo)


if __name__ == "__main__":
    main()
