import { ExternalLink, TriangleAlert } from "lucide-react";

const PATHBUILDER_URL = "https://pathbuilder2e.com/app.html";

export function PathbuilderEmbed() {
  return <section className="pathbuilder-embed" aria-labelledby="pathbuilder-embed-title">
    <h2 id="pathbuilder-embed-title" className="visually-hidden">Pathbuilder 2e</h2>
    <div className="pathbuilder-frame-wrap">
      <iframe
        src={PATHBUILDER_URL}
        title="Fiche de personnage dans Pathbuilder 2e"
        referrerPolicy="strict-origin-when-cross-origin"
        allow="clipboard-read; clipboard-write"
      />
    </div>
    <footer className="pathbuilder-fallback"><p><TriangleAlert size={15} /><span>Pathbuilder fonctionne indépendamment du gestionnaire de butins. Si l’intégration ne s’affiche pas, ouvrez-le séparément.</span></p><a className="button secondary" href={PATHBUILDER_URL} target="_blank" rel="noreferrer"><ExternalLink size={16} />Ouvrir séparément</a></footer>
  </section>;
}
