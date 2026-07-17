import type { ReactNode } from "react";
import type { Visibility } from "../lib/types";

export function VisibilityBadge({ visibility }: { visibility: Visibility }) {
  const labels: Record<Visibility, string> = {
    gm_only: "MJ uniquement",
    ready: "Prêt à révéler",
    players: "Visible joueurs",
  };
  return <span className={`visibility visibility-${visibility}`}>{labels[visibility]}</span>;
}

export function EmptyState({ title, children }: { title: string; children: ReactNode }) {
  return <div className="empty-state"><strong>{title}</strong><p>{children}</p></div>;
}

export function SectionHeading({ eyebrow, title, actions }: { eyebrow?: string; title: string; actions?: ReactNode }) {
  return (
    <div className="section-heading">
      <div>{eyebrow && <p className="eyebrow">{eyebrow}</p>}<h2>{title}</h2></div>
      {actions && <div className="section-actions">{actions}</div>}
    </div>
  );
}

export function LoadingScreen({ label = "Ouverture des registres…" }: { label?: string }) {
  return <main className="state-screen"><div className="loader-sigil">G</div><p>{label}</p></main>;
}

export function ErrorPanel({ error, onRetry }: { error: string; onRetry?: () => void }) {
  return (
    <div className="error-panel" role="alert">
      <strong>Le registre ne répond pas</strong>
      <p>{error}</p>
      {onRetry && <button className="button secondary" onClick={onRetry}>Réessayer</button>}
    </div>
  );
}
