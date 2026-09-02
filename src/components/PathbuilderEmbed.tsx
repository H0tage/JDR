import { ExternalLink, TriangleAlert } from "lucide-react";

const PATHBUILDER_URL = "https://pathbuilder2e.com/app.html";

export function PathbuilderEmbed() {
  return <section className="pathbuilder-embed" aria-labelledby="pathbuilder-embed-title">
    <header>
      <div>
        <p className="eyebrow">Outil externe intégré</p>
        <h2 id="pathbuilder-embed-title">Pathbuilder 2e</h2>
        <p>Vous utilisez directement Pathbuilder dans le registre. Les modifications sont enregistrées par Pathbuilder et restent indépendantes du gestionnaire de butins.</p>
      </div>
      <a className="button secondary" href={PATHBUILDER_URL} target="_blank" rel="noreferrer"><ExternalLink size={16} />Ouvrir séparément</a>
    </header>
    <div className="pathbuilder-frame-wrap">
      <iframe
        src={PATHBUILDER_URL}
        title="Fiche de personnage dans Pathbuilder 2e"
        referrerPolicy="strict-origin-when-cross-origin"
        allow="clipboard-read; clipboard-write"
      />
    </div>
    <p className="pathbuilder-fallback"><TriangleAlert size={15} /><span>Si Pathbuilder ne s’affiche pas ou si votre navigateur bloque sa connexion, utilisez « Ouvrir séparément ».</span></p>
  </section>;
}
