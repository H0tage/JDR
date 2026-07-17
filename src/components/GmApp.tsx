import {
  Archive,
  BookOpenText,
  Building2,
  ChevronRight,
  CircleDollarSign,
  Eye,
  EyeOff,
  Handshake,
  LayoutDashboard,
  LogOut,
  Menu,
  Network,
  NotebookPen,
  Plus,
  Save,
  Settings,
  ShieldAlert,
  Sparkles,
  Trash2,
  Users,
  X,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import {
  addJournalEntry,
  applyMilestone,
  currentSession,
  deleteJournalEntry,
  loadGmData,
  saveContact,
  signInWithPassword,
  signOut,
  spendFavor,
  subscribeToCampaign,
  updateFactionDetails,
  updateJournalVisibility,
  updateRelationship,
  updateSettings,
} from "../lib/api";
import { quoteService, unlockedServices } from "../lib/domain";
import { hasSupabaseConfig, supabase } from "../lib/supabase";
import type {
  CampaignData,
  CampaignSettings,
  Contact,
  FactionOverview,
  JournalEntry,
  Milestone,
  Relationship,
  RelationshipColor,
  Service,
  Visibility,
} from "../lib/types";
import { EmptyState, ErrorPanel, LoadingScreen, SectionHeading, VisibilityBadge } from "./ui";

type Tab = "dashboard" | "journal" | "factions" | "services" | "contacts" | "politics" | "progression" | "settings";

const navItems: Array<{ id: Tab; label: string; icon: typeof LayoutDashboard }> = [
  { id: "dashboard", label: "Tableau de bord", icon: LayoutDashboard },
  { id: "journal", label: "Journal", icon: NotebookPen },
  { id: "factions", label: "Factions", icon: Building2 },
  { id: "services", label: "Services", icon: Handshake },
  { id: "contacts", label: "Contacts et dettes", icon: Users },
  { id: "politics", label: "Politique", icon: Network },
  { id: "progression", label: "Progression", icon: BookOpenText },
  { id: "settings", label: "Réglages", icon: Settings },
];

function useDemoMode() {
  return new URLSearchParams(window.location.search).get("demo") === "1";
}

export function GmApp() {
  const demo = useDemoMode();
  const [checking, setChecking] = useState(!demo);
  const [authenticated, setAuthenticated] = useState(demo);

  useEffect(() => {
    if (demo) return;
    void currentSession().then((session) => {
      setAuthenticated(Boolean(session));
      setChecking(false);
    });
    const subscription = supabase?.auth.onAuthStateChange((_event, session) => {
      setAuthenticated(Boolean(session));
      setChecking(false);
    });
    return () => subscription?.data.subscription.unsubscribe();
  }, [demo]);

  if (checking) return <LoadingScreen label="Vérification du sceau…" />;
  if (!authenticated) return <LoginPanel />;
  return <GmWorkspace demo={demo} />;
}

function LoginPanel() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await signInWithPassword(email.trim(), password);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Connexion impossible.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="login-shell">
      <section className="login-card">
        <div className="login-mark">MJ</div>
        <p className="eyebrow">Registre confidentiel</p>
        <h1>Écran du maître de jeu</h1>
        <p>Les informations de cet espace ne sont jamais envoyées à la vue des joueurs.</p>
        {!hasSupabaseConfig && <ErrorPanel error="Les variables Supabase ne sont pas configurées." />}
        <form className="stack-form" onSubmit={submit}>
          <label>Adresse e-mail<input type="email" required value={email} onChange={(event) => setEmail(event.target.value)} autoComplete="email" /></label>
          <label>Mot de passe<input type="password" required value={password} onChange={(event) => setPassword(event.target.value)} autoComplete="current-password" /></label>
          {error && <p className="form-error">{error}</p>}
          <button className="button primary" disabled={busy || !hasSupabaseConfig}>{busy ? "Ouverture…" : "Ouvrir le registre"}</button>
        </form>
        <a className="demo-link" href="?demo=1">Consulter l’aperçu sans connexion</a>
        <a className="back-link" href="/">Retour à l’entrée</a>
      </section>
    </main>
  );
}

function GmWorkspace({ demo }: { demo: boolean }) {
  const [tab, setTab] = useState<Tab>("dashboard");
  const [menuOpen, setMenuOpen] = useState(false);
  const [data, setData] = useState<CampaignData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [notice, setNotice] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setError(null);
    try {
      setData(await loadGmData(demo));
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Chargement impossible.");
    } finally {
      setLoading(false);
    }
  }, [demo]);

  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => {
    if (!data || demo) return;
    return subscribeToCampaign(data.settings.campaign_id, () => void refresh());
  }, [data?.settings.campaign_id, demo, refresh]);

  function announce(message: string) {
    setNotice(message);
    window.setTimeout(() => setNotice(null), 3200);
  }

  async function mutate(action: () => Promise<void>, success: string, local?: (previous: CampaignData) => CampaignData) {
    try {
      if (demo) {
        if (local) setData((previous) => previous ? local(structuredClone(previous)) : previous);
      } else {
        await action();
        await refresh();
      }
      announce(success);
      return true;
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Modification impossible.");
      return false;
    }
  }

  if (loading) return <LoadingScreen />;
  if (!data) return (
    <main className="state-screen">
      <ErrorPanel error={error ?? "Aucune donnée disponible."} onRetry={() => void refresh()} />
      <a className="button secondary" href="?demo=1">Ouvrir l’aperçu local</a>
    </main>
  );

  const active = navItems.find((item) => item.id === tab)!;
  return (
    <div className="app-shell gm-shell">
      <aside className={menuOpen ? "sidebar open" : "sidebar"}>
        <div className="brand-block"><span className="brand-glyph">G</span><div><strong>Registres de Geb</strong><small>Blood Lords · MJ</small></div></div>
        <button className="mobile-close" onClick={() => setMenuOpen(false)} aria-label="Fermer le menu"><X /></button>
        <nav>
          {navItems.map((item) => {
            const Icon = item.icon;
            return <button key={item.id} className={tab === item.id ? "active" : ""} onClick={() => { setTab(item.id); setMenuOpen(false); }}><Icon size={18} /><span>{item.label}</span></button>;
          })}
        </nav>
        <div className="sidebar-footer">
          {demo && <span className="demo-pill">Mode aperçu</span>}
          <button onClick={() => demo ? window.location.assign("/MJsecretscreen/") : void signOut()}><LogOut size={17} />{demo ? "Quitter l’aperçu" : "Se déconnecter"}</button>
        </div>
      </aside>
      {menuOpen && <button className="scrim" onClick={() => setMenuOpen(false)} aria-label="Fermer" />}
      <main className="workspace">
        <header className="topbar">
          <button className="menu-button" onClick={() => setMenuOpen(true)}><Menu /></button>
          <div><p className="eyebrow">Volume {data.settings.current_volume} sur 6</p><h1>{active.label}</h1></div>
          <a className="player-shortcut" href="/playerscreen/" target="_blank" rel="noreferrer"><Eye size={18} /><span>Vue joueurs</span></a>
        </header>
        {error && <div className="inline-error"><ShieldAlert size={18} /><span>{error}</span><button onClick={() => setError(null)}><X size={16} /></button></div>}
        {notice && <div className="toast"><Save size={17} />{notice}</div>}
        <div className="workspace-body">
          {tab === "dashboard" && <DashboardTab data={data} onNavigate={setTab} />}
          {tab === "journal" && <JournalTab data={data} mutate={mutate} />}
          {tab === "factions" && <FactionsTab data={data} mutate={mutate} />}
          {tab === "services" && <ServicesTab data={data} mutate={mutate} />}
          {tab === "contacts" && <ContactsTab data={data} mutate={mutate} />}
          {tab === "politics" && <PoliticsTab data={data} mutate={mutate} />}
          {tab === "progression" && <ProgressionTab data={data} mutate={mutate} />}
          {tab === "settings" && <SettingsTab data={data} mutate={mutate} />}
        </div>
      </main>
    </div>
  );
}

type Mutate = (action: () => Promise<void>, success: string, local?: (previous: CampaignData) => CampaignData) => Promise<boolean>;

function DashboardTab({ data, onNavigate }: { data: CampaignData; onNavigate: (tab: Tab) => void }) {
  const liked = data.factions.filter((f) => f.rp >= data.settings.liked_threshold).length;
  const usable = data.factions.reduce((sum, faction) => sum + faction.jf, 0);
  const tensions = data.factions.filter((f) => f.tension > 0).length;
  const ready = data.relationships.filter((r) => r.visibility === "ready").length + data.contacts.filter((c) => c.visibility === "ready").length;
  return (
    <div className="page-stack">
      <section className="hero-panel compact">
        <div><p className="eyebrow">État de la campagne</p><h2>Le pouvoir se tient dans les détails.</h2><p>Les totaux proviennent exclusivement du journal. Les informations prêtes restent invisibles jusqu’à leur révélation.</p></div>
        <button className="button light" onClick={() => onNavigate("journal")}><Plus size={17} />Nouvelle entrée</button>
      </section>
      <section className="metric-grid">
        <article><span>Factions appréciées</span><strong>{liked}<small>/ 6</small></strong></article>
        <article><span>JF utilisables</span><strong>{usable}</strong></article>
        <article><span>Tensions actives</span><strong>{tensions}</strong></article>
        <article><span>Prêts à révéler</span><strong>{ready}</strong></article>
      </section>
      <SectionHeading eyebrow="Position publique" title="Les six factions" actions={<button className="text-button" onClick={() => onNavigate("factions")}>Modifier les fiches <ChevronRight size={16} /></button>} />
      <section className="faction-grid">
        {data.factions.map((faction) => <FactionCard key={faction.faction_id} faction={faction} settings={data.settings} />)}
      </section>
      <section className="dashboard-columns">
        <div className="panel">
          <div className="panel-title"><div><p className="eyebrow">Activité récente</p><h3>Journal</h3></div><button className="icon-button" onClick={() => onNavigate("journal")}><ChevronRight /></button></div>
          <div className="mini-list">
            {data.journal.slice(0, 4).map((entry) => <div key={entry.id}><span className="date-box">{new Date(`${entry.occurred_on}T00:00:00`).toLocaleDateString("fr-CH", { day: "2-digit", month: "short" })}</span><div><strong>{entry.title}</strong><small>{entry.faction_name} · V{entry.volume}</small></div><DeltaSummary entry={entry} /></div>)}
            {data.journal.length === 0 && <EmptyState title="Journal vide">Ajoutez le premier changement de réputation.</EmptyState>}
          </div>
        </div>
        <div className="panel">
          <div className="panel-title"><div><p className="eyebrow">À surveiller</p><h3>Conséquences</h3></div><button className="icon-button" onClick={() => onNavigate("factions")}><ChevronRight /></button></div>
          <div className="consequence-list">
            {data.factions.filter((f) => f.next_consequence || f.tension > 0).map((faction) => <div key={faction.faction_id} style={{ "--accent": faction.accent } as React.CSSProperties}><strong>{faction.short_name}</strong><p>{faction.next_consequence || faction.tension_label}</p></div>)}
            {!data.factions.some((f) => f.next_consequence || f.tension > 0) && <EmptyState title="Aucune alerte">La politique est calme — pour l’instant.</EmptyState>}
          </div>
        </div>
      </section>
    </div>
  );
}

function FactionCard({ faction, settings }: { faction: FactionOverview; settings: CampaignSettings }) {
  const progress = Math.min(100, (faction.rp / settings.revered_threshold) * 100);
  return (
    <article className="faction-card" style={{ "--accent": faction.accent } as React.CSSProperties}>
      <div className="faction-card-head"><div className="faction-monogram">{faction.short_name.slice(0, 2).toUpperCase()}</div><div><h3>{faction.short_name}</h3><p>{faction.domain}</p></div></div>
      <div className="rank-line"><strong>{faction.status}</strong><span>{faction.rp} RP</span></div>
      <div className="progress-track"><span style={{ width: `${progress}%` }} /></div>
      <div className="faction-stats"><div><span>Faveurs</span><strong>{faction.jf} JF</strong></div><div><span>Tension</span><strong>{faction.tension_label}</strong></div></div>
      {faction.public_summary && <p className="faction-summary">{faction.public_summary}</p>}
    </article>
  );
}

function DeltaSummary({ entry }: { entry: JournalEntry }) {
  const deltas = [entry.rp_delta ? `${entry.rp_delta > 0 ? "+" : ""}${entry.rp_delta} RP` : "", entry.jf_delta ? `${entry.jf_delta > 0 ? "+" : ""}${entry.jf_delta} JF` : "", entry.tension_delta ? `${entry.tension_delta > 0 ? "+" : ""}${entry.tension_delta} T` : ""].filter(Boolean);
  return <span className={`delta-summary ${deltas.some((d) => d.startsWith("-")) ? "negative" : ""}`}>{deltas.join(" · ") || "Note"}</span>;
}

function JournalTab({ data, mutate }: { data: CampaignData; mutate: Mutate }) {
  const [open, setOpen] = useState(false);
  const [filter, setFilter] = useState("all");
  const [form, setForm] = useState({ faction_id: data.factions[0]?.faction_id ?? "", occurred_on: new Date().toISOString().slice(0, 10), volume: data.settings.current_volume, title: "", details: "", operation: "reputation_gain", amount: 1, visibility: "gm_only" as Visibility, source_reference: "" });
  const entries = filter === "all" ? data.journal : data.journal.filter((entry) => entry.faction_id === filter);

  function deltas() {
    const amount = Math.max(0, Number(form.amount));
    if (form.operation === "reputation_gain") return { rp_delta: amount, jf_delta: amount, tension_delta: 0 };
    if (form.operation === "reputation_loss") return { rp_delta: -amount, jf_delta: 0, tension_delta: 0 };
    if (form.operation === "favor_spend") return { rp_delta: 0, jf_delta: -amount, tension_delta: 0 };
    if (form.operation === "tension_up") return { rp_delta: 0, jf_delta: 0, tension_delta: amount };
    return { rp_delta: 0, jf_delta: 0, tension_delta: -amount };
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    const entry = { campaign_id: data.settings.campaign_id, faction_id: form.faction_id, occurred_on: form.occurred_on, volume: Number(form.volume), title: form.title.trim(), details: form.details.trim() || null, ...deltas(), visibility: form.visibility, source_reference: form.source_reference.trim() || null };
    const factionName = data.factions.find((f) => f.faction_id === entry.faction_id)?.short_name;
    await mutate(
      () => addJournalEntry(entry),
      "Entrée ajoutée au journal.",
      (previous) => {
        previous.journal.unshift({ id: crypto.randomUUID(), faction_name: factionName, ...entry });
        const faction = previous.factions.find((f) => f.faction_id === entry.faction_id)!;
        faction.rp = Math.max(0, faction.rp + entry.rp_delta);
        faction.jf = Math.max(0, Math.min(previous.settings.jf_cap, faction.jf + entry.jf_delta));
        faction.tension = Math.max(0, Math.min(previous.settings.tension_max, faction.tension + entry.tension_delta));
        return previous;
      },
    );
    setOpen(false);
    setForm((value) => ({ ...value, title: "", details: "", amount: 1, source_reference: "" }));
  }

  return (
    <div className="page-stack">
      <SectionHeading eyebrow="Source unique des totaux" title="Journal de réputation" actions={<button className="button primary" onClick={() => setOpen(true)}><Plus size={17} />Ajouter</button>} />
      <div className="toolbar"><label>Faction<select value={filter} onChange={(event) => setFilter(event.target.value)}><option value="all">Toutes</option>{data.factions.map((f) => <option key={f.faction_id} value={f.faction_id}>{f.short_name}</option>)}</select></label><span>{entries.length} entrée{entries.length > 1 ? "s" : ""}</span></div>
      <div className="table-wrap"><table className="data-table journal-table"><thead><tr><th>Date</th><th>Événement</th><th>Faction</th><th>Volume</th><th>Variation</th><th>Visibilité</th><th /></tr></thead><tbody>{entries.map((entry) => <tr key={entry.id}><td>{new Date(`${entry.occurred_on}T00:00:00`).toLocaleDateString("fr-CH")}</td><td><strong>{entry.title}</strong>{entry.details && <small>{entry.details}</small>}{entry.source_reference && <em>{entry.source_reference}</em>}</td><td>{entry.faction_name}</td><td>V{entry.volume}</td><td><DeltaSummary entry={entry} /></td><td><select className="visibility-select" value={entry.visibility} onChange={(event) => { const visibility = event.target.value as Visibility; void mutate(() => updateJournalVisibility(entry.id, visibility), "Visibilité modifiée.", (previous) => { previous.journal.find((item) => item.id === entry.id)!.visibility = visibility; return previous; }); }}><option value="gm_only">MJ uniquement</option><option value="ready">Prêt à révéler</option><option value="players">Visible joueurs</option></select></td><td><button className="icon-button danger" onClick={() => window.confirm("Supprimer cette entrée et recalculer les totaux ?") && void mutate(() => deleteJournalEntry(entry.id), "Entrée supprimée.", (previous) => { previous.journal = previous.journal.filter((item) => item.id !== entry.id); const faction = previous.factions.find((f) => f.faction_id === entry.faction_id)!; faction.rp = Math.max(0, faction.rp - entry.rp_delta); faction.jf = Math.max(0, faction.jf - entry.jf_delta); faction.tension = Math.max(0, faction.tension - entry.tension_delta); return previous; })}><Trash2 size={16} /></button></td></tr>)}</tbody></table></div>
      {open && <div className="modal-backdrop"><form className="modal-card" onSubmit={submit}><div className="modal-head"><div><p className="eyebrow">Nouvelle variation</p><h3>Ajouter au journal</h3></div><button type="button" className="icon-button" onClick={() => setOpen(false)}><X /></button></div><div className="form-grid"><label>Faction<select value={form.faction_id} onChange={(e) => setForm({ ...form, faction_id: e.target.value })}>{data.factions.map((f) => <option key={f.faction_id} value={f.faction_id}>{f.short_name}</option>)}</select></label><label>Date<input type="date" value={form.occurred_on} onChange={(e) => setForm({ ...form, occurred_on: e.target.value })} /></label><label>Opération<select value={form.operation} onChange={(e) => setForm({ ...form, operation: e.target.value })}><option value="reputation_gain">Gain de réputation</option><option value="reputation_loss">Perte de réputation</option><option value="favor_spend">Dépense de faveurs</option><option value="tension_up">Hausse de tension</option><option value="tension_down">Réduction de tension</option></select></label><label>Valeur<input type="number" min="1" value={form.amount} onChange={(e) => setForm({ ...form, amount: Number(e.target.value) })} /></label><label>Volume<select value={form.volume} onChange={(e) => setForm({ ...form, volume: Number(e.target.value) })}>{[1,2,3,4,5,6].map((v) => <option key={v} value={v}>Volume {v}</option>)}</select></label><label>Visibilité<select value={form.visibility} onChange={(e) => setForm({ ...form, visibility: e.target.value as Visibility })}><option value="gm_only">MJ uniquement</option><option value="ready">Prêt à révéler</option><option value="players">Visible joueurs</option></select></label><label className="span-2">Titre<input required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} placeholder="Ex. Crise de la ferme résolue" /></label><label className="span-2">Détails<textarea value={form.details} onChange={(e) => setForm({ ...form, details: e.target.value })} /></label><label className="span-2">Référence<input value={form.source_reference} onChange={(e) => setForm({ ...form, source_reference: e.target.value })} placeholder="Volume et page, si applicable" /></label></div><div className="modal-actions"><button type="button" className="button secondary" onClick={() => setOpen(false)}>Annuler</button><button className="button primary">Enregistrer</button></div></form></div>}
    </div>
  );
}

function FactionsTab({ data, mutate }: { data: CampaignData; mutate: Mutate }) {
  const [selected, setSelected] = useState(data.factions[0].faction_id);
  const faction = data.factions.find((f) => f.faction_id === selected)!;
  const [draft, setDraft] = useState({ public_summary: faction.public_summary ?? "", gm_notes: faction.gm_notes ?? "", next_consequence: faction.next_consequence ?? "", is_player_visible: faction.is_player_visible });
  useEffect(() => setDraft({ public_summary: faction.public_summary ?? "", gm_notes: faction.gm_notes ?? "", next_consequence: faction.next_consequence ?? "", is_player_visible: faction.is_player_visible }), [faction.faction_id]);
  async function save(event: FormEvent) {
    event.preventDefault();
    const patch = { public_summary: draft.public_summary || null, gm_notes: draft.gm_notes || null, next_consequence: draft.next_consequence || null, is_player_visible: draft.is_player_visible };
    await mutate(() => updateFactionDetails(data.settings.campaign_id, faction.faction_id, patch), "Fiche de faction enregistrée.", (previous) => { Object.assign(previous.factions.find((f) => f.faction_id === faction.faction_id)!, patch); return previous; });
  }
  return <div className="page-stack"><SectionHeading eyebrow="Six pouvoirs de Geb" title="Fiches de faction" /><div className="split-layout"><div className="selection-list">{data.factions.map((item) => <button key={item.faction_id} className={item.faction_id === selected ? "selected" : ""} onClick={() => setSelected(item.faction_id)} style={{ "--accent": item.accent } as React.CSSProperties}><span className="selection-dot" /><div><strong>{item.short_name}</strong><small>{item.status} · {item.rp} RP</small></div><ChevronRight size={17} /></button>)}</div><form className="panel detail-form" onSubmit={save}><div className="detail-hero" style={{ "--accent": faction.accent } as React.CSSProperties}><div className="faction-monogram large">{faction.short_name.slice(0, 2).toUpperCase()}</div><div><p className="eyebrow">{faction.domain}</p><h2>{faction.name}</h2><p>{faction.public_description}</p></div></div><div className="stat-strip"><div><span>Position</span><strong>{faction.status}</strong></div><div><span>Réputation</span><strong>{faction.rp} RP</strong></div><div><span>Faveurs</span><strong>{faction.jf} JF</strong></div><div><span>Tension</span><strong>{faction.tension_label}</strong></div></div><label className="toggle-row"><input type="checkbox" checked={draft.is_player_visible} onChange={(e) => setDraft({ ...draft, is_player_visible: e.target.checked })} /><span><strong>Afficher cette faction aux joueurs</strong><small>Masquer la fiche entière tant qu’elle n’est pas pertinente.</small></span></label><label>Résumé visible des joueurs<textarea value={draft.public_summary} onChange={(e) => setDraft({ ...draft, public_summary: e.target.value })} placeholder="Ce que les personnages savent de leur relation actuelle…" /></label><label>Notes privées du MJ<textarea value={draft.gm_notes} onChange={(e) => setDraft({ ...draft, gm_notes: e.target.value })} /></label><label>Prochaine conséquence<textarea value={draft.next_consequence} onChange={(e) => setDraft({ ...draft, next_consequence: e.target.value })} placeholder="Une réaction préparée, sans effet automatique…" /></label><div className="form-footer"><span>{unlockedServices(faction.rp, faction.slug, data.settings)}</span><button className="button primary"><Save size={17} />Enregistrer</button></div></form></div></div>;
}

function ServicesTab({ data, mutate }: { data: CampaignData; mutate: Mutate }) {
  const [factionId, setFactionId] = useState(data.factions[0].faction_id);
  const [serviceId, setServiceId] = useState(data.services.find((s) => s.faction_id === factionId)?.id ?? data.services[0].id);
  const [advantage, setAdvantage] = useState<"none" | "first_liked" | "admired_discount">("none");
  const [title, setTitle] = useState("");
  const faction = data.factions.find((f) => f.faction_id === factionId)!;
  const services = data.services.filter((s) => s.faction_id === factionId);
  const service = data.services.find((s) => s.id === serviceId && s.faction_id === factionId) ?? services[0];
  const quote = quoteService(service, faction, data.settings, advantage);
  function changeFaction(id: string) { setFactionId(id); setServiceId(data.services.find((s) => s.faction_id === id)!.id); setAdvantage("none"); }
  async function confirmSpend() {
    const requestTitle = title.trim() || `${service.scale} — ${service.domain}`;
    await mutate(() => spendFavor({ campaignId: data.settings.campaign_id, factionId, title: requestTitle, cost: quote.cost, volume: data.settings.current_volume, visibility: "ready" }), "Dépense ajoutée au journal, prête à révéler.", (previous) => { const target = previous.factions.find((f) => f.faction_id === factionId)!; target.jf -= quote.cost; previous.journal.unshift({ id: crypto.randomUUID(), campaign_id: previous.settings.campaign_id, faction_id: factionId, faction_name: target.short_name, occurred_on: new Date().toISOString().slice(0,10), volume: previous.settings.current_volume, title: requestTitle, details: "Service de faction accordé.", rp_delta: 0, jf_delta: -quote.cost, tension_delta: 0, visibility: "ready", source_reference: null }); return previous; });
    setTitle("");
  }
  return <div className="page-stack"><SectionHeading eyebrow="Réserve de faveurs" title="Planificateur de services" /><section className="service-planner panel"><div className="planner-controls"><label>Faction<select value={factionId} onChange={(e) => changeFaction(e.target.value)}>{data.factions.map((f) => <option key={f.faction_id} value={f.faction_id}>{f.short_name} — {f.jf} JF</option>)}</select></label><label>Service<select value={service.id} onChange={(e) => setServiceId(e.target.value)}>{services.map((s) => <option key={s.id} value={s.id}>{s.scale} · {s.domain}</option>)}</select></label><label>Avantage<select value={advantage} onChange={(e) => setAdvantage(e.target.value as typeof advantage)}><option value="none">Aucun</option><option value="first_liked">Premier service apprécié</option><option value="admired_discount">Réduction admirée</option></select></label><label>Objet de la demande<input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Pourquoi le groupe sollicite la faction" /></label></div><div className={`quote-card ${quote.allowed ? "allowed" : "blocked"}`}><span>{quote.allowed ? <Sparkles size={22} /> : <ShieldAlert size={22} />}</span><div><small>{quote.reason}</small><strong>{quote.cost} JF</strong><p>Solde après demande : {quote.balanceAfter} JF</p></div><button className="button primary" disabled={!quote.allowed} onClick={() => void confirmSpend()}>Accorder et journaliser</button></div></section><div className="table-wrap"><table className="data-table"><thead><tr><th>Faction</th><th>Échelle</th><th>Accès</th><th>Coût</th><th>Domaine et exemples</th><th>Garde-fou</th><th>Fréquence</th></tr></thead><tbody>{data.services.map((item) => <tr key={item.id}><td>{item.faction_name}</td><td><span className={`scale scale-${item.scale.toLowerCase()}`}>{item.scale}</span></td><td>{item.required_rp} RP</td><td>{item.base_cost} JF</td><td><strong>{item.domain}</strong><small>{item.examples}</small></td><td>{item.safeguard}</td><td>{item.frequency}</td></tr>)}</tbody></table></div></div>;
}

function ContactsTab({ data, mutate }: { data: CampaignData; mutate: Mutate }) {
  const [selected, setSelected] = useState<Contact | null>(null);
  const grouped = data.factions.map((faction) => ({ faction, contacts: data.contacts.filter((contact) => contact.faction_id === faction.faction_id) }));
  async function save(event: FormEvent) { event.preventDefault(); if (!selected) return; await mutate(() => saveContact(selected), "Contact enregistré.", (previous) => { const index = previous.contacts.findIndex((c) => c.id === selected.id); if (index >= 0) previous.contacts[index] = selected; else previous.contacts.push(selected); return previous; }); setSelected(null); }
  return <div className="page-stack"><SectionHeading eyebrow="Personnes, promesses et conséquences" title="Contacts et dettes" /><div className="contact-grid">{grouped.map(({ faction, contacts }) => <section className="panel contact-group" key={faction.faction_id} style={{ "--accent": faction.accent } as React.CSSProperties}><div className="contact-group-title"><span className="selection-dot" /><div><h3>{faction.short_name}</h3><small>{contacts.length} contact{contacts.length > 1 ? "s" : ""}</small></div><button className="icon-button" onClick={() => setSelected({ id: crypto.randomUUID(), campaign_id: data.settings.campaign_id, faction_id: faction.faction_id, faction_name: faction.short_name, name: "", role: "", state: "À introduire", attitude: "Neutre", promise_debt: null, due_text: null, gm_notes: null, next_consequence: null, visibility: "gm_only", is_primary: false })}><Plus /></button></div>{contacts.map((contact) => <button className="contact-row" key={contact.id} onClick={() => setSelected({ ...contact })}><div><strong>{contact.name}</strong><small>{contact.role}</small></div><div><VisibilityBadge visibility={contact.visibility} /><span>{contact.state}</span></div></button>)}{contacts.length === 0 && <EmptyState title="Aucun contact">Ajoutez une personne liée à cette faction.</EmptyState>}</section>)}</div>{selected && <div className="modal-backdrop"><form className="modal-card wide" onSubmit={save}><div className="modal-head"><div><p className="eyebrow">{selected.faction_name}</p><h3>{selected.name || "Nouveau contact"}</h3></div><button type="button" className="icon-button" onClick={() => setSelected(null)}><X /></button></div><div className="form-grid"><label>Nom<input required value={selected.name} onChange={(e) => setSelected({ ...selected, name: e.target.value })} /></label><label>Rôle<input value={selected.role} onChange={(e) => setSelected({ ...selected, role: e.target.value })} /></label><label>État<select value={selected.state} onChange={(e) => setSelected({ ...selected, state: e.target.value })}>{["À introduire","Actif","Distant","Compromis","Hostile","Indisponible"].map((v) => <option key={v}>{v}</option>)}</select></label><label>Attitude<input value={selected.attitude} onChange={(e) => setSelected({ ...selected, attitude: e.target.value })} /></label><label>Visibilité<select value={selected.visibility} onChange={(e) => setSelected({ ...selected, visibility: e.target.value as Visibility })}><option value="gm_only">MJ uniquement</option><option value="ready">Prêt à révéler</option><option value="players">Visible joueurs</option></select></label><label className="check-label"><input type="checkbox" checked={selected.is_primary} onChange={(e) => setSelected({ ...selected, is_primary: e.target.checked })} />Contact principal</label><label className="span-2">Promesse ou dette<textarea value={selected.promise_debt ?? ""} onChange={(e) => setSelected({ ...selected, promise_debt: e.target.value || null })} /></label><label>Échéance<input value={selected.due_text ?? ""} onChange={(e) => setSelected({ ...selected, due_text: e.target.value || null })} /></label><label>Prochaine conséquence<input value={selected.next_consequence ?? ""} onChange={(e) => setSelected({ ...selected, next_consequence: e.target.value || null })} /></label><label className="span-2">Notes privées<textarea value={selected.gm_notes ?? ""} onChange={(e) => setSelected({ ...selected, gm_notes: e.target.value || null })} /></label></div><div className="modal-actions"><button type="button" className="button secondary" onClick={() => setSelected(null)}>Annuler</button><button className="button primary">Enregistrer</button></div></form></div>}</div>;
}

function PoliticsTab({ data, mutate }: { data: CampaignData; mutate: Mutate }) {
  const [selected, setSelected] = useState<Relationship | null>(null);
  const [draft, setDraft] = useState<{ headline: string; detail: string; color: RelationshipColor; visibility: Visibility } | null>(null);
  const [dossier, setDossier] = useState(data.dossiers[0]?.id ?? "");
  const selectedDossier = data.dossiers.find((item) => item.id === dossier);
  function relation(source: FactionOverview, target: FactionOverview) { return data.relationships.find((item) => item.source_faction_id === source.faction_id && item.target_faction_id === target.faction_id); }
  function openRelationship(item: Relationship) {
    setSelected(item);
    setDraft({ headline: item.headline, detail: item.detail, color: item.color ?? defaultColor(item), visibility: item.visibility });
  }
  function closeRelationship() {
    setSelected(null);
    setDraft(null);
  }
  function defaultHeadline(item: Relationship) { return item.default_headline ?? item.headline; }
  function defaultDetail(item: Relationship) { return item.default_detail ?? item.detail; }
  function defaultColor(item: Relationship): RelationshipColor {
    if (item.default_color) return item.default_color;
    if (item.tone === "hostility") return "hostile";
    if (item.tone === "tension" || item.tone === "unclear") return "uncertain";
    return "favorable";
  }
  function normalizedOverride(value: string, fallback: string) {
    const normalized = value.trim();
    return !normalized || normalized === fallback.trim() ? null : normalized;
  }
  async function saveRelationship(event: FormEvent) {
    event.preventDefault();
    if (!selected || !draft) return;
    const fallbackHeadline = defaultHeadline(selected);
    const fallbackDetail = defaultDetail(selected);
    const headlineOverride = normalizedOverride(draft.headline, fallbackHeadline);
    const detailOverride = normalizedOverride(draft.detail, fallbackDetail);
    const fallbackColor = defaultColor(selected);
    const colorOverride = draft.color === fallbackColor ? null : draft.color;
    const saved = await mutate(
      () => updateRelationship(selected.id, {
        headline_override: headlineOverride,
        detail_override: detailOverride,
        color_override: colorOverride,
        visibility: draft.visibility,
      }),
      "Relation enregistrée.",
      (previous) => {
        const item = previous.relationships.find((candidate) => candidate.id === selected.id)!;
        item.headline_override = headlineOverride;
        item.detail_override = detailOverride;
        item.color_override = colorOverride;
        item.headline = headlineOverride ?? fallbackHeadline;
        item.detail = detailOverride ?? fallbackDetail;
        item.color = colorOverride ?? fallbackColor;
        item.visibility = draft.visibility;
        return previous;
      },
    );
    if (saved) closeRelationship();
  }

  return (
    <div className="page-stack">
      <SectionHeading eyebrow="Lecture directionnelle" title="Politique des factions" />
      <div className="legend-row color-legend">
        <span><i className="tone-dot favorable" />Favorable</span>
        <span><i className="tone-dot uncertain" />Tendue ou ambiguë</span>
        <span><i className="tone-dot hostile" />Hostile</span>
        <p>Le fond de chaque case indique l’état de la relation.</p>
      </div>
      <div className="matrix-wrap">
        <table className="politics-matrix">
          <thead><tr><th>Point de vue ↓</th>{data.factions.map((f) => <th key={f.faction_id}>{f.short_name}</th>)}</tr></thead>
          <tbody>{data.factions.map((source) => <tr key={source.faction_id}><th>{source.short_name}</th>{data.factions.map((target) => {
            const item = relation(source, target);
            return <td key={target.faction_id} className={!item ? "diagonal" : item.color}><button disabled={!item} onClick={() => item && openRelationship(item)}>{item ? <><strong>{item.headline}</strong><span>{item.visibility === "players" ? <Eye size={14} /> : item.visibility === "ready" ? <Sparkles size={14} /> : <EyeOff size={14} />}</span></> : "—"}</button></td>;
          })}</tr>)}</tbody>
        </table>
      </div>
      <section className="dossier-section">
        <div className="dossier-picker"><p className="eyebrow">15 dossiers bilatéraux</p><select value={dossier} onChange={(e) => setDossier(e.target.value)}>{data.dossiers.map((item) => <option key={item.id} value={item.id}>{item.pair_name}</option>)}</select></div>
        {selectedDossier && <article className="dossier-card"><div className="dossier-core"><span>Noyau canon</span><p>{selectedDossier.canon_core}</p></div><div className="dossier-directions"><div><span>Première faction → seconde</span><p>{selectedDossier.a_to_b}</p></div><div><span>Seconde faction → première</span><p>{selectedDossier.b_to_a}</p></div></div><div className="dossier-grid"><div><span>Intérêt commun</span><p>{selectedDossier.common_interest}</p></div><div><span>Ligne de fracture</span><p>{selectedDossier.fracture}</p></div><div><span>Déclencheurs utiles</span><p>{selectedDossier.triggers}</p></div><div><span>Scène prête à jouer</span><p>{selectedDossier.scene_hook}</p></div></div><footer>{selectedDossier.evidence_note}</footer></article>}
      </section>
      {selected && draft && <div className="modal-backdrop">
        <form className="modal-card wide" onSubmit={saveRelationship}>
          <div className="modal-head"><div><p className="eyebrow">{selected.source_name} → {selected.target_name}</p><h3>{draft.headline.trim() || defaultHeadline(selected)}</h3></div><button type="button" className="icon-button" onClick={closeRelationship}><X /></button></div>
          <div className="relationship-editor">
            <div className="relationship-field">
              <div className="relationship-field-head"><label htmlFor="relationship-headline">Titre affiché dans la matrice</label><button id="relationship-headline-reset" type="button" className="text-button" onClick={() => setDraft((current) => current ? { ...current, headline: defaultHeadline(selected) } : current)}>Reprendre le défaut</button></div>
              <input id="relationship-headline" value={draft.headline} onChange={(event) => setDraft((current) => current ? { ...current, headline: event.target.value } : current)} placeholder={defaultHeadline(selected)} />
              <small>Vider le champ réactive automatiquement le titre de référence.</small>
            </div>
            <div className="relationship-field">
              <div className="relationship-field-head"><label htmlFor="relationship-detail">Description affichée</label><button id="relationship-detail-reset" type="button" className="text-button" onClick={() => setDraft((current) => current ? { ...current, detail: defaultDetail(selected) } : current)}>Reprendre le défaut</button></div>
              <textarea id="relationship-detail" value={draft.detail} onChange={(event) => setDraft((current) => current ? { ...current, detail: event.target.value } : current)} placeholder={defaultDetail(selected)} />
              <small>Ce même texte apparaîtra côté joueurs lorsque la relation sera publique.</small>
            </div>
            <div className="relationship-field">
              <div className="relationship-field-head"><label>Code couleur</label><button id="relationship-color-reset" type="button" className="text-button" onClick={() => setDraft((current) => current ? { ...current, color: defaultColor(selected) } : current)}>Reprendre le défaut</button></div>
              <div className="relationship-colors">
                <button type="button" className={draft.color === "favorable" ? "active" : ""} onClick={() => setDraft((current) => current ? { ...current, color: "favorable" } : current)}><i className="tone-dot favorable" />Favorable</button>
                <button type="button" className={draft.color === "uncertain" ? "active" : ""} onClick={() => setDraft((current) => current ? { ...current, color: "uncertain" } : current)}><i className="tone-dot uncertain" />Tendue ou ambiguë</button>
                <button type="button" className={draft.color === "hostile" ? "active" : ""} onClick={() => setDraft((current) => current ? { ...current, color: "hostile" } : current)}><i className="tone-dot hostile" />Hostile</button>
              </div>
              <small>La couleur choisie est également utilisée dans la matrice des joueurs lorsque cette relation est publique.</small>
            </div>
          </div>
          <div className="relation-meta">
            <VisibilityBadge visibility={draft.visibility} />
            {(normalizedOverride(draft.headline, defaultHeadline(selected)) || normalizedOverride(draft.detail, defaultDetail(selected))) && <span className="customized-copy">Texte personnalisé</span>}
            {draft.color !== defaultColor(selected) && <span className="customized-copy">Couleur personnalisée</span>}
          </div>
          <div className="reveal-actions"><button type="button" className={draft.visibility === "gm_only" ? "active" : ""} onClick={() => setDraft((current) => current ? { ...current, visibility: "gm_only" } : current)}><EyeOff />MJ uniquement</button><button type="button" className={draft.visibility === "ready" ? "active" : ""} onClick={() => setDraft((current) => current ? { ...current, visibility: "ready" } : current)}><Sparkles />Prête à révéler</button><button type="button" className={draft.visibility === "players" ? "active" : ""} onClick={() => setDraft((current) => current ? { ...current, visibility: "players" } : current)}><Eye />Visible joueurs</button></div>
          <div className="modal-actions"><button type="button" className="button secondary" onClick={closeRelationship}>Annuler</button><button className="button primary"><Save size={17} />Enregistrer</button></div>
        </form>
      </div>}
    </div>
  );
}

function ProgressionTab({ data, mutate }: { data: CampaignData; mutate: Mutate }) {
  const volumeGuides = [
    ["Présenter les factions", "Nommer un contact et un service concret à chaque seuil atteint.", "Ne pas ajouter des RP uniquement pour accélérer la progression."],
    ["Introduire les Convoyeurs", "Faire apparaître au plus une conséquence importante par chapitre.", "Éviter de transformer chaque détour en test de loyauté."],
    ["Soutenir la diplomatie", "Employer contacts et faveurs pour préparer les scènes d’influence.", "Ne pas rallonger les sous-systèmes d’Influence existants."],
    ["Valoriser les temps morts", "Autoriser projets, travaux, recherches et faveurs institutionnelles.", "Les services ne doivent pas effacer les coûts narratifs majeurs."],
    ["Réutiliser les relations", "Faire revenir contacts, dettes et promesses antérieures.", "Éviter les bonus universels sans lien avec la fiction."],
    ["Conclure les alliances", "Appliquer d’abord les raccourcis gratuits prévus par l’aventure.", "Ne pas faire payer ce que le texte accorde déjà."],
  ];
  async function apply(item: Milestone) { if (!window.confirm(`Appliquer « ${item.title} » au journal ?`)) return; await mutate(() => applyMilestone(item.id), "Jalon appliqué au journal.", (previous) => { previous.milestones.find((m) => m.id === item.id)!.applied = true; const add = (factionId: string | null, delta: number, label: string) => { if (!factionId || !delta) return; const faction = previous.factions.find((f) => f.faction_id === factionId)!; faction.rp = Math.max(0, faction.rp + delta); if (delta > 0) faction.jf = Math.min(previous.settings.jf_cap, faction.jf + delta); previous.journal.unshift({ id: crypto.randomUUID(), campaign_id: previous.settings.campaign_id, faction_id: factionId, faction_name: faction.short_name, occurred_on: new Date().toISOString().slice(0,10), volume: item.volume, title: `${item.title} — ${label}`, details: item.condition, rp_delta: delta, jf_delta: delta > 0 ? delta : 0, tension_delta: 0, visibility: "ready", source_reference: item.source_reference }); }; add(item.beneficiary_faction_id, item.rp_gain, "gain"); add(item.harmed_faction_id, item.rp_loss, "perte"); return previous; }); }
  return <div className="page-stack"><SectionHeading eyebrow="Six volumes, une campagne" title="Progression MJ" /><section className="volume-track">{volumeGuides.map((guide, index) => <article key={index} className={data.settings.current_volume === index + 1 ? "current" : data.settings.current_volume > index + 1 ? "past" : ""}><span>{index + 1}</span><div><strong>{guide[0]}</strong><p>{guide[1]}</p><small>{guide[2]}</small></div></article>)}</section><SectionHeading eyebrow="Récompenses officielles vérifiées" title="Jalons du volume 1" /><div className="table-wrap"><table className="data-table"><thead><tr><th>Volume</th><th>Jalon</th><th>Gain</th><th>Perte liée</th><th>Condition</th><th>État</th></tr></thead><tbody>{data.milestones.map((item) => <tr key={item.id}><td>V{item.volume}</td><td><strong>{item.title}</strong><small>{item.source_reference}</small></td><td>{item.beneficiary_name ? `${item.beneficiary_name} +${item.rp_gain}` : "—"}</td><td>{item.harmed_name ? `${item.harmed_name} ${item.rp_loss}` : "—"}</td><td>{item.condition}</td><td>{item.applied ? <span className="applied">Appliqué</span> : <button className="button tiny" onClick={() => void apply(item)}>Appliquer</button>}</td></tr>)}</tbody></table></div><p className="footnote">Ce relevé initial couvre le volume 1 et complète sa lecture sans la remplacer. Chaque application crée des lignes distinctes dans le journal.</p></div>;
}

function SettingsTab({ data, mutate }: { data: CampaignData; mutate: Mutate }) {
  const [draft, setDraft] = useState({ ...data.settings });
  async function submit(event: FormEvent) { event.preventDefault(); await mutate(() => updateSettings(draft), "Configuration enregistrée.", (previous) => { previous.settings = draft; return previous; }); }
  const numeric = (key: keyof CampaignSettings, label: string, help: string, min = 0, max?: number) => <label className="setting-row"><span><strong>{label}</strong><small>{help}</small></span><input type="number" min={min} max={max} value={draft[key] as number} onChange={(e) => setDraft({ ...draft, [key]: Number(e.target.value) })} /></label>;
  return <div className="page-stack"><SectionHeading eyebrow="Paramètres de la maison" title="Règles du système" /><form className="settings-layout" onSubmit={submit}><section className="panel settings-panel"><h3>Progression</h3><label className="setting-row"><span><strong>Volume actuel</strong><small>Utilisé par défaut dans le journal et les demandes.</small></span><select value={draft.current_volume} onChange={(e) => setDraft({ ...draft, current_volume: Number(e.target.value) })}>{[1,2,3,4,5,6].map((v) => <option key={v} value={v}>Volume {v}</option>)}</select></label>{numeric("liked_threshold", "Seuil Apprécié", "Débloque les demandes mineures.")}{numeric("admired_threshold", "Seuil Admiré", "Débloque les demandes modérées.")}{numeric("revered_threshold", "Seuil Révéré", "Débloque les demandes majeures.")}{numeric("carters_major_threshold", "Majeure des Convoyeurs", "Seuil spécial, une fois dans la campagne.")}</section><section className="panel settings-panel"><h3>Faveurs</h3>{numeric("jf_cap", "Plafond souple de JF", "L’excédent doit être converti en avantage nommé.")}{numeric("minor_cost", "Demande mineure", "Coût de base en JF.")}{numeric("moderate_cost", "Demande modérée", "Coût de base en JF.")}{numeric("major_cost", "Demande majeure", "Coût de base en JF.")}{numeric("admired_discount", "Réduction admirée", "Première demande modérée du volume.")}</section><section className="panel settings-panel"><h3>Tension et joueurs</h3>{numeric("tension_max", "Tension maximale", "À ce niveau, la relation est rompue.", 1)}{numeric("tension_surcharge_level", "Niveau de surcharge", "Ajoute un coût aux demandes.")}{numeric("tension_surcharge", "Surcharge en JF", "Coût ajouté au niveau défini.")}<label className="toggle-row"><input type="checkbox" checked={draft.show_numeric_tension} onChange={(e) => setDraft({ ...draft, show_numeric_tension: e.target.checked })} /><span><strong>Afficher la tension chiffrée</strong><small>Sinon les joueurs voient seulement une formulation narrative.</small></span></label></section><div className="settings-submit"><p>Les modifications s’appliquent immédiatement aux calculs, sans réécrire le journal.</p><button className="button primary"><Save size={17} />Enregistrer les réglages</button></div></form></div>;
}
