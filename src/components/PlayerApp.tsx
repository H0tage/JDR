import { BookOpen, Eye, Handshake, Network, Printer, ScrollText, Shield, Users } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { loadPlayerData } from "../lib/api";
import { unlockedServices } from "../lib/domain";
import type { CampaignData, FactionOverview } from "../lib/types";
import { EmptyState, ErrorPanel, LoadingScreen, SectionHeading } from "./ui";

type PlayerTab = "relations" | "services" | "politics" | "history";

export function PlayerApp() {
  const demo = new URLSearchParams(window.location.search).get("demo") === "1";
  const [data, setData] = useState<CampaignData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<PlayerTab>("relations");

  const refresh = useCallback(async () => {
    try {
      setData(await loadPlayerData(demo));
      setError(null);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Chargement impossible.");
    } finally {
      setLoading(false);
    }
  }, [demo]);

  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => {
    if (demo) return;
    const refreshWhenVisible = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    const interval = window.setInterval(refreshWhenVisible, 20_000);
    window.addEventListener("focus", refreshWhenVisible);
    document.addEventListener("visibilitychange", refreshWhenVisible);
    return () => {
      window.clearInterval(interval);
      window.removeEventListener("focus", refreshWhenVisible);
      document.removeEventListener("visibilitychange", refreshWhenVisible);
    };
  }, [demo, refresh]);

  if (loading) return <LoadingScreen label="Consultation des registres publics…" />;
  if (!data) return <main className="state-screen"><ErrorPanel error={error ?? "Vue indisponible."} onRetry={() => void refresh()} /><a className="button secondary" href="?demo=1">Ouvrir l’aperçu</a></main>;

  return (
    <div className="player-shell">
      <header className="player-header">
        <a className="player-brand" href="/"><span>G</span><div><strong>Relations du groupe</strong><small>Blood Lords · Volume {data.settings.current_volume}</small></div></a>
        <button className="button ghost print-button" onClick={() => window.print()}><Printer size={17} />Imprimer</button>
      </header>
      <section className="player-hero">
        <div><p className="eyebrow">Position publique en Geb</p><h1>Les faveurs se gagnent.<br />Les dettes, elles, se souviennent.</h1><p>Cette page présente uniquement les informations que vos personnages ont apprises en jeu.</p></div>
        <div className="player-seal"><Shield size={36} /><span>Registre<br />public</span></div>
      </section>
      <nav className="player-tabs">
        <button className={tab === "relations" ? "active" : ""} onClick={() => setTab("relations")}><Eye size={17} />Relations</button>
        <button className={tab === "services" ? "active" : ""} onClick={() => setTab("services")}><Handshake size={17} />Services</button>
        <button className={tab === "politics" ? "active" : ""} onClick={() => setTab("politics")}><Network size={17} />Politique connue</button>
        <button className={tab === "history" ? "active" : ""} onClick={() => setTab("history")}><ScrollText size={17} />Chronique</button>
      </nav>
      <main className="player-content">
        {error && <ErrorPanel error={error} onRetry={() => void refresh()} />}
        {tab === "relations" && <PlayerRelations data={data} />}
        {tab === "services" && <PlayerServices data={data} />}
        {tab === "politics" && <PlayerPolitics data={data} />}
        {tab === "history" && <PlayerHistory data={data} />}
      </main>
      <footer className="player-footer"><span>Aide de jeu non officielle</span><p>Les RP représentent votre position publique et ne sont jamais dépensés. Les JF servent à solliciter un service.</p></footer>
    </div>
  );
}

function PlayerRelations({ data }: { data: CampaignData }) {
  const visibleFactions = data.factions.filter((faction) => faction.is_player_visible);
  return (
    <div className="page-stack">
      <SectionHeading eyebrow="Réputation et faveurs" title="Vos relations" />
      <section className="player-faction-grid">{visibleFactions.map((faction) => <PlayerFactionCard key={faction.faction_id} faction={faction} data={data} />)}</section>
      <SectionHeading eyebrow="Personnes connues" title="Vos contacts" />
      <section className="known-contact-grid">
        {data.contacts.map((contact) => <article key={contact.id}><div className="contact-icon"><Users size={19} /></div><div><small>{contact.faction_name}</small><h3>{contact.name}</h3><p>{contact.role}</p>{contact.promise_debt && <blockquote>{contact.promise_debt}</blockquote>}</div></article>)}
        {data.contacts.length === 0 && <EmptyState title="Aucun contact révélé">Les noms utiles apparaîtront ici au fil de la campagne.</EmptyState>}
      </section>
      <section className="rules-card"><BookOpen size={24} /><div><h3>Comment lire ces valeurs ?</h3><div className="rules-grid"><p><strong>RP</strong> Votre réputation publique. Elle ne se dépense jamais.</p><p><strong>JF</strong> Votre réserve de faveurs auprès de chaque faction.</p><p><strong>Coûts</strong> Mineure {data.settings.minor_cost} · Modérée {data.settings.moderate_cost} · Majeure {data.settings.major_cost} JF.</p><p><strong>Négociation</strong> Un test peut améliorer la vitesse, la discrétion ou la contrepartie.</p></div></div></section>
    </div>
  );
}

function PlayerFactionCard({ faction, data }: { faction: FactionOverview; data: CampaignData }) {
  const progress = Math.min(100, (faction.rp / data.settings.revered_threshold) * 100);
  const access = faction.tension_label === "Rupture" ? "Services suspendus" : unlockedServices(faction.rp, faction.slug, data.settings);
  return <article className="player-faction-card" style={{ "--accent": faction.accent } as React.CSSProperties}><header><div className="faction-monogram">{faction.short_name.slice(0,2).toUpperCase()}</div><div><p>{faction.domain}</p><h2>{faction.short_name}</h2></div></header><p className="player-description">{faction.public_description}</p><div className="player-rank"><span>{faction.status}</span><strong>{faction.rp} RP</strong></div><div className="progress-track"><span style={{ width: `${progress}%` }} /></div><div className="player-values"><div><small>Faveurs disponibles</small><strong>{faction.jf} JF</strong></div><div><small>État de la relation</small><strong>{data.settings.show_numeric_tension ? `Tension ${faction.tension}` : faction.tension_label}</strong></div></div><p className="unlock-line">{access}</p>{faction.public_summary && <blockquote>{faction.public_summary}</blockquote>}</article>;
}

function PlayerServices({ data }: { data: CampaignData }) {
  const accessible = data.services;
  return <div className="page-stack"><SectionHeading eyebrow="Ce que vos alliances peuvent obtenir" title="Services débloqués" /><p className="section-intro">Une faveur ouvre l’accès au service de base. Les biens, matériaux et prestations ordinaires restent payants sauf indication du MJ.</p><div className="service-card-grid">{accessible.map((service) => { const faction = data.factions.find((item) => item.faction_id === service.faction_id)!; return <article key={service.id} style={{ "--accent": faction.accent } as React.CSSProperties}><header><span>{service.faction_name}</span><strong>{service.scale}</strong></header><h3>{service.domain}</h3><p>{service.examples}</p><div><span>{service.base_cost} JF</span><small>{service.frequency}</small></div></article>; })}{accessible.length === 0 && <EmptyState title="Aucun service débloqué">À 5 RP, une faction commence à accorder des demandes mineures.</EmptyState>}</div></div>;
}

function PlayerPolitics({ data }: { data: CampaignData }) {
  function relation(source: FactionOverview, target: FactionOverview) { return data.relationships.find((item) => item.source_faction_id === source.faction_id && item.target_faction_id === target.faction_id); }
  const hasRelations = data.relationships.length > 0;
  return <div className="page-stack"><SectionHeading eyebrow="Informations découvertes en jeu" title="Politique connue" />{hasRelations ? <><p className="section-intro">La matrice se lit par ligne : elle montre comment la première faction considère la seconde. Les relations peuvent être asymétriques.</p><div className="matrix-wrap player-matrix"><table className="politics-matrix"><thead><tr><th>Point de vue ↓</th>{data.factions.map((f) => <th key={f.faction_id}>{f.short_name}</th>)}</tr></thead><tbody>{data.factions.map((source) => <tr key={source.faction_id}><th>{source.short_name}</th>{data.factions.map((target) => { const item = relation(source,target); return <td key={target.faction_id} className={source.faction_id === target.faction_id ? "diagonal" : item?.tone ?? "unknown"}>{item ? <div><strong>{item.headline}</strong><p>{item.detail}</p></div> : "?"}</td>; })}</tr>)}</tbody></table></div></> : <EmptyState title="Le jeu des factions reste opaque">Les relations révélées par le MJ apparaîtront ici, une direction à la fois.</EmptyState>}</div>;
}

function PlayerHistory({ data }: { data: CampaignData }) {
  return <div className="page-stack"><SectionHeading eyebrow="Événements rendus publics" title="Chronique des factions" /><div className="public-timeline">{data.journal.map((entry) => <article key={entry.id}><time>{new Date(`${entry.occurred_on}T00:00:00`).toLocaleDateString("fr-CH", { day: "numeric", month: "long", year: "numeric" })}</time><div><span>{entry.faction_name} · Volume {entry.volume}</span><h3>{entry.title}</h3>{entry.details && <p>{entry.details}</p>}</div><strong>{[entry.rp_delta ? `${entry.rp_delta > 0 ? "+" : ""}${entry.rp_delta} RP` : "", entry.jf_delta && entry.rp_delta === 0 ? `${entry.jf_delta} JF` : "", entry.tension_delta ? "Relation modifiée" : ""].filter(Boolean).join(" · ")}</strong></article>)}{data.journal.length === 0 && <EmptyState title="Aucun événement public">La chronique s’enrichira à mesure que vos actes seront connus.</EmptyState>}</div></div>;
}
