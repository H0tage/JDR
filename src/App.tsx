import { ArrowRight, Eye, LockKeyhole, Skull } from "lucide-react";
import { GmApp } from "./components/GmApp";
import { PlayerApp } from "./components/PlayerApp";

function Landing() {
  return (
    <main className="landing-shell">
      <div className="landing-noise" />
      <section className="landing-card">
        <div className="sigil" aria-hidden="true"><Skull size={34} /></div>
        <p className="eyebrow">Blood Lords · Geb</p>
        <h1>Les Registres<br />de Griseplainte</h1>
        <p className="landing-lead">
          Réputation, faveurs et politique des six factions, tenues avec la précision d’un percepteur
          et la discrétion d’un bâtisseur.
        </p>
        <div className="landing-actions">
          <a className="portal-card player" href="/playerscreen/">
            <Eye size={20} />
            <span><strong>Vue des joueurs</strong><small>Relations et faveurs révélées</small></span>
            <ArrowRight size={18} />
          </a>
          <a className="portal-card gm" href="/MJsecretscreen/">
            <LockKeyhole size={20} />
            <span><strong>Registre du MJ</strong><small>Accès authentifié</small></span>
            <ArrowRight size={18} />
          </a>
        </div>
        <p className="legal-line">Aide de jeu non officielle pour Pathfinder Adventure Path: Blood Lords.</p>
      </section>
    </main>
  );
}

export function App() {
  const path = window.location.pathname.toLowerCase();
  if (path.startsWith("/mjsecretscreen")) return <GmApp />;
  if (path.startsWith("/playerscreen")) return <PlayerApp />;
  return <Landing />;
}
