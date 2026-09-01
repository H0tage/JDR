import {
  Archive,
  BookOpenText,
  Building2,
  CalendarClock,
  ChevronRight,
  ClipboardList,
  Eye,
  EyeOff,
  Gem,
  ImagePlus,
  LayoutDashboard,
  LogOut,
  Menu,
  NotebookPen,
  Plus,
  Save,
  Settings,
  ShieldAlert,
  Sparkles,
  Sun,
  Trash2,
  Users,
  X,
  Moon,
} from "lucide-react";
import { lazy, Suspense, useCallback, useEffect, useState, type FormEvent } from "react";
import {
  addJournalEntry,
  currentSession,
  contactPortraitUrl,
  deleteContactPortrait,
  deleteJournalEntry,
  loadGmData,
  resolveMilestone,
  saveContact,
  saveSessionPrep,
  signInWithPassword,
  signOut,
  spendFavor,
  subscribeToCampaign,
  uploadContactPortrait,
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
  MilestoneEffect,
  MilestoneEffectTemplate,
  MilestoneStatus,
  Relationship,
  RelationshipColor,
  Visibility,
} from "../lib/types";
import { EmptyState, ErrorPanel, LoadingScreen, SectionHeading, VisibilityBadge } from "./ui";
import { BestiaryTab } from "./BestiaryTab";
import { QuestJournalTab } from "./QuestJournalTab";
import { QuestWritingTab } from "./QuestWritingTab";
import { createCampaignInvite, listCampaignInvites, listCampaignMembers, removeCampaignPlayer, revokeCampaignInvite, type CampaignInvite, type CampaignMember } from "../lib/campaignPortalApi";
import { listCampaignPlayerPages, type CampaignPlayerPage } from "../lib/playerPageApi";

const ArchivesTab = lazy(() => import("./ReferenceTables").then((module) => ({ default: module.ArchivesTab })));
const LootManager = lazy(() => import("./LootManager").then((module) => ({ default: module.LootManager })));

type Tab = "dashboard" | "journal" | "factions" | "contacts" | "milestones" | "loot" | "references" | "bestiary" | "settings";
type AppTheme = "light" | "original" | "dark";

const navItems: Array<{ id: Tab; label: string; icon: typeof LayoutDashboard }> = [
  { id: "dashboard", label: "Tableau de bord", icon: LayoutDashboard },
  { id: "journal", label: "Journal", icon: NotebookPen },
  { id: "factions", label: "Factions", icon: Building2 },
  { id: "contacts", label: "Contacts et dettes", icon: Users },
  { id: "milestones", label: "Jalons", icon: BookOpenText },
  { id: "loot", label: "Butins", icon: Gem },
  { id: "references", label: "Références", icon: Archive },
  { id: "bestiary", label: "Bestiaire", icon: BookOpenText },
];

function useDemoMode() {
  return new URLSearchParams(window.location.search).get("demo") === "1";
}

function storedAppTheme(): AppTheme {
  try {
    const current = window.localStorage.getItem("blood-lords-player-theme-v2");
    if (current === "light" || current === "original" || current === "dark") return current;
    return window.localStorage.getItem("blood-lords-player-theme") === "dark" ? "original" : "light";
  } catch {
    return "light";
  }
}

export function GmApp({ campaignId, campaignSlug }: { campaignId: string; campaignSlug?: string }) {
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
  return <GmWorkspace campaignId={campaignId} campaignSlug={campaignSlug} demo={demo} />;
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

function GmWorkspace({ campaignId, campaignSlug, demo }: { campaignId: string; campaignSlug?: string; demo: boolean }) {
  const [tab, setTab] = useState<Tab>("dashboard");
  const [menuOpen, setMenuOpen] = useState(false);
  const [data, setData] = useState<CampaignData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [notice, setNotice] = useState<string | null>(null);
  const [theme, setTheme] = useState<AppTheme>(storedAppTheme);

  useEffect(() => {
    try {
      window.localStorage.setItem("blood-lords-player-theme-v2", theme);
    } catch {
      // L’affichage reste fonctionnel lorsqu’un navigateur bloque le stockage local.
    }
  }, [theme]);

  const refresh = useCallback(async () => {
    setError(null);
    try {
      setData(await loadGmData(campaignId, demo));
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Chargement impossible.");
    } finally {
      setLoading(false);
    }
  }, [campaignId, demo]);

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

  const active = navItems.find((item) => item.id === tab) ?? { id: "settings" as Tab, label: "Réglages", icon: Settings };
  const themeClass = theme === "dark" ? "github-dark" : theme;
  return (
    <div className={`app-shell gm-shell gm-theme-${themeClass}`}>
      <aside className={menuOpen ? "sidebar open" : "sidebar"}>
        <div className="brand-block"><span className="brand-glyph"><span>BL</span></span><div><strong>Registres de Geb</strong><small>Blood Lords · MJ</small></div></div>
        <button className="mobile-close" onClick={() => setMenuOpen(false)} aria-label="Fermer le menu"><X /></button>
        <nav>
          {navItems.map((item) => {
            const Icon = item.icon;
            return <button key={item.id} className={tab === item.id ? "active" : ""} onClick={() => { setTab(item.id); setMenuOpen(false); }}><Icon size={18} /><span>{item.label}</span></button>;
          })}
        </nav>
        <div className="sidebar-footer">
          {demo && <span className="demo-pill">Mode aperçu</span>}
          <button onClick={() => { setTab("settings"); setMenuOpen(false); }}><Settings size={17} />Réglages</button>
          <button onClick={() => demo ? window.location.assign("/MJsecretscreen/") : void signOut()}><LogOut size={17} />{demo ? "Quitter l’aperçu" : "Se déconnecter"}</button>
        </div>
      </aside>
      {menuOpen && <button className="scrim" onClick={() => setMenuOpen(false)} aria-label="Fermer" />}
      <main className="workspace">
        <header className="topbar">
          <button className="menu-button" onClick={() => setMenuOpen(true)}><Menu /></button>
          <div><p className="eyebrow">Volume {data.settings.current_volume} sur 6</p><h1>{active.label}</h1></div>
          <fieldset className="gm-theme-picker"><legend>Thème</legend>
            <label className={theme === "light" ? "active" : ""}><input type="radio" name="gm-theme" checked={theme === "light"} onChange={() => setTheme("light")} /><Sun size={14} /><span>Clair</span></label>
            <label className={theme === "original" ? "active" : ""}><input type="radio" name="gm-theme" checked={theme === "original"} onChange={() => setTheme("original")} /><Moon size={14} /><span>Original</span></label>
            <label className={theme === "dark" ? "active" : ""}><input type="radio" name="gm-theme" checked={theme === "dark"} onChange={() => setTheme("dark")} /><Moon size={14} /><span>Sombre</span></label>
          </fieldset>
          <a className="player-shortcut" href={demo ? "/playerscreen/?demo=1" : `/campaign/${campaignSlug ?? campaignId}/playerscreen`} target="_blank" rel="noreferrer"><Eye size={18} /><span>Vue joueurs</span></a>
        </header>
        {error && <div className="inline-error"><ShieldAlert size={18} /><span>{error}</span><button onClick={() => setError(null)}><X size={16} /></button></div>}
        {notice && <div className="toast"><Save size={17} />{notice}</div>}
        <div className="workspace-body">
          {tab === "dashboard" && <DashboardTab data={data} mutate={mutate} onNavigate={setTab} />}
          {tab === "journal" && <JournalHub data={data} mutate={mutate} demo={demo} onChanged={refresh} onNotice={announce} onError={setError} />}
          {tab === "factions" && <FactionsHub data={data} mutate={mutate} />}
          {tab === "contacts" && <ContactsTab data={data} mutate={mutate} demo={demo} />}
          {tab === "milestones" && <ProgressionTab data={data} mutate={mutate} demo={demo} />}
          {tab === "loot" && <Suspense fallback={<LoadingScreen label="Ouverture du registre des butins…" />}><LootManager campaignId={data.settings.campaign_id} demo={demo} onNotice={announce} onError={setError} /></Suspense>}
          {tab === "references" && <ReferencesHub campaignId={data.settings.campaign_id} demo={demo} onNotice={announce} onError={setError} />}
          {tab === "bestiary" && <BestiaryTab campaignId={data.settings.campaign_id} entries={data.bestiary} demo={demo} onChanged={refresh} onNotice={announce} onError={setError} />}
          {tab === "settings" && <SettingsTab data={data} mutate={mutate} campaignId={campaignId} />}
        </div>
      </main>
    </div>
  );
}

type Mutate = (action: () => Promise<void>, success: string, local?: (previous: CampaignData) => CampaignData) => Promise<boolean>;

function DashboardTab({ data, mutate, onNavigate }: { data: CampaignData; mutate: Mutate; onNavigate: (tab: Tab) => void }) {
  const currentMilestones = data.milestones.filter((item) => item.volume === data.settings.current_volume);
  const pendingMilestones = currentMilestones.filter((item) => item.status === "pending");
  const activeTensions = data.factions.filter((item) => item.tension > 0);
  const dueContacts = data.contacts.filter((item) => item.due_text);
  const [editingPrep, setEditingPrep] = useState(false);
  const [prepDraft, setPrepDraft] = useState(data.sessionPrep);

  useEffect(() => setPrepDraft(data.sessionPrep), [data.sessionPrep]);

  async function savePrep(event: FormEvent) {
    event.preventDefault();
    const saved = {
      ...prepDraft,
      objective: prepDraft.objective?.trim() || null,
      scenes: prepDraft.scenes?.trim() || null,
      reminders: prepDraft.reminders?.trim() || null,
      notes: prepDraft.notes?.trim() || null,
    };
    const completed = await mutate(
      () => saveSessionPrep(saved),
      "Préparation de séance enregistrée.",
      (previous) => ({ ...previous, sessionPrep: saved }),
    );
    if (completed) setEditingPrep(false);
  }

  const activeFactions = data.factions.filter((item) => item.rp > 0 || item.jf > 0 || item.tension > 0 || item.public_summary);
  const summaries = [
    pendingMilestones.length > 0 && { tab: "milestones" as Tab, icon: ClipboardList, label: `${pendingMilestones.length} jalon${pendingMilestones.length > 1 ? "s" : ""} à résoudre` },
    activeTensions.length > 0 && { tab: "factions" as Tab, icon: ShieldAlert, label: `${activeTensions.length} tension${activeTensions.length > 1 ? "s" : ""} active${activeTensions.length > 1 ? "s" : ""}` },
    dueContacts.length > 0 && { tab: "contacts" as Tab, icon: Users, label: `${dueContacts.length} suivi${dueContacts.length > 1 ? "s" : ""} de contact` },
  ].filter(Boolean) as Array<{ tab: Tab; icon: typeof ClipboardList; label: string }>;

  return <div className="page-stack dashboard-stack">
    <section className="dashboard-heading">
      <div><p className="eyebrow">Poste de pilotage</p><h2>Campagne · Volume {data.settings.current_volume}</h2><p>Préparez la prochaine séance, puis accédez directement aux registres utiles.</p></div>
      <button className="button primary" onClick={() => onNavigate("journal")}><Plus size={17} />Nouvelle entrée</button>
    </section>

    <section className="session-prep-card panel">
      <div className="session-prep-head"><div><p className="eyebrow">Préparation privée</p><h3>Prochaine séance</h3></div>{!editingPrep && <button className="button secondary tiny" onClick={() => setEditingPrep(true)}>Modifier</button>}</div>
      {editingPrep ? <form className="session-prep-form" onSubmit={savePrep}>
        <label>Objectif actuel<input value={prepDraft.objective ?? ""} onChange={(event) => setPrepDraft({ ...prepDraft, objective: event.target.value })} placeholder="Ex. Conclure l’affaire de la banque" /></label>
        <label>Scènes à préparer<textarea value={prepDraft.scenes ?? ""} onChange={(event) => setPrepDraft({ ...prepDraft, scenes: event.target.value })} placeholder="Une scène ou un élément par ligne" /></label>
        <label>À ne pas oublier<textarea value={prepDraft.reminders ?? ""} onChange={(event) => setPrepDraft({ ...prepDraft, reminders: event.target.value })} placeholder="PNJ, objets, règles ou conséquences" /></label>
        <label>Notes de séance<textarea value={prepDraft.notes ?? ""} onChange={(event) => setPrepDraft({ ...prepDraft, notes: event.target.value })} placeholder="Notes privées libres" /></label>
        <div className="session-prep-actions"><button type="button" className="button secondary" onClick={() => { setPrepDraft(data.sessionPrep); setEditingPrep(false); }}>Annuler</button><button className="button primary"><Save size={16} />Enregistrer</button></div>
      </form> : <div className="session-prep-content">
        <div className="session-objective"><CalendarClock size={20} /><div><span>Objectif actuel</span><strong>{data.sessionPrep.objective || "À définir"}</strong></div></div>
        <div><span>Scènes à préparer</span><p>{data.sessionPrep.scenes || "Aucune scène notée."}</p></div>
        <div><span>À ne pas oublier</span><p>{data.sessionPrep.reminders || "Aucun rappel noté."}</p></div>
        <div><span>Notes de séance</span><p>{data.sessionPrep.notes || "Aucune note privée."}</p></div>
      </div>}
    </section>

    {summaries.length > 0 && <section className="dashboard-summary-grid">{summaries.map((summary) => { const Icon = summary.icon; return <button key={summary.tab} onClick={() => onNavigate(summary.tab)}><Icon size={19} /><span>{summary.label}</span><ChevronRight size={17} /></button>; })}</section>}

    <section className="dashboard-main-grid">
      <div className="panel dashboard-priorities"><div className="panel-title"><div><p className="eyebrow">À préparer / à décider</p><h3>Priorités</h3></div></div><div className="priority-list">
        {data.factions.filter((item) => item.tension > 0).slice(0, 3).map((faction) => <button key={faction.faction_id} onClick={() => onNavigate("factions")}><i style={{ background: faction.accent }} /><div><strong>{faction.short_name}</strong><span>{faction.tension_label}</span></div><ChevronRight size={16} /></button>)}
        {dueContacts.slice(0, 2).map((contact) => <button key={contact.id} onClick={() => onNavigate("contacts")}><CalendarClock size={16} /><div><strong>{contact.name}</strong><span>{contact.due_text}</span></div><ChevronRight size={16} /></button>)}
        {pendingMilestones.slice(0, 2).map((milestone) => <button key={milestone.id} onClick={() => onNavigate("milestones")}><ClipboardList size={16} /><div><strong>{milestone.title}</strong><span>{milestone.condition}</span></div><ChevronRight size={16} /></button>)}
        {!data.factions.some((item) => item.tension > 0) && dueContacts.length === 0 && pendingMilestones.length === 0 && <EmptyState title="Aucune priorité active">Ajoutez une échéance ou préparez le prochain volume.</EmptyState>}
      </div></div>
      <div className="panel dashboard-recent"><div className="panel-title"><div><p className="eyebrow">Activité récente</p><h3>Journal</h3></div><button className="icon-button" onClick={() => onNavigate("journal")}><ChevronRight /></button></div><div className="mini-list">
        {data.journal.slice(0, 3).map((entry) => <div key={entry.id}><span className="date-box">{new Date(`${entry.occurred_on}T00:00:00`).toLocaleDateString("fr-CH", { day: "2-digit", month: "short" })}</span><div><strong>{entry.title}</strong><small>{entry.faction_name} · V{entry.volume}</small></div><DeltaSummary entry={entry} /></div>)}
        {data.journal.length === 0 && <EmptyState title="Journal vide">Ajoutez le premier changement de réputation.</EmptyState>}
      </div></div>
    </section>

    <section><SectionHeading eyebrow="Relations à suivre" title="Factions" actions={<button className="text-button" onClick={() => onNavigate("factions")}>Ouvrir les fiches <ChevronRight size={16} /></button>} /><div className="faction-overview-grid">
      {activeFactions.map((faction) => <button key={faction.faction_id} className="faction-overview-row" onClick={() => onNavigate("factions")} style={{ "--accent": faction.accent } as React.CSSProperties}><span className="faction-monogram">{faction.short_name.slice(0, 2).toUpperCase()}</span><span><strong>{faction.short_name}</strong><small>{faction.status} · {faction.jf} JF</small></span><em>{faction.tension_label}</em><ChevronRight size={16} /></button>)}
      {activeFactions.length === 0 && <EmptyState title="Aucune relation active">Les six factions restent encore à distance du groupe.</EmptyState>}
    </div></section>
  </div>;
}

function DeltaSummary({ entry }: { entry: JournalEntry }) {
  const deltas = [entry.rp_delta ? `${entry.rp_delta > 0 ? "+" : ""}${entry.rp_delta} RP` : "", entry.jf_delta ? `${entry.jf_delta > 0 ? "+" : ""}${entry.jf_delta} JF` : "", entry.tension_delta ? `${entry.tension_delta > 0 ? "+" : ""}${entry.tension_delta} T` : ""].filter(Boolean);
  return <span className={`delta-summary ${deltas.some((d) => d.startsWith("-")) ? "negative" : ""}`}>{deltas.join(" · ") || "Note"}</span>;
}

function VisibilityToggle({ value, onChange, compact = false }: { value: Visibility; onChange: (visibility: Visibility) => void; compact?: boolean }) {
  return <div className={`visibility-toggle${compact ? " compact" : ""}`} role="group" aria-label="Visibilité">
    <button type="button" className={value === "gm_only" ? "active gm" : ""} aria-pressed={value === "gm_only"} onClick={() => onChange("gm_only")}><EyeOff size={14} />MJ</button>
    <button type="button" className={value === "players" ? "active public" : ""} aria-pressed={value === "players"} onClick={() => onChange("players")}><Eye size={14} />Public</button>
  </div>;
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
      <div className="table-wrap"><table className="data-table journal-table"><thead><tr><th>Date</th><th>Événement</th><th>Faction</th><th>Volume</th><th>Variation</th><th>Visibilité</th><th /></tr></thead><tbody>{entries.map((entry) => <tr key={entry.id}><td>{new Date(`${entry.occurred_on}T00:00:00`).toLocaleDateString("fr-CH")}</td><td><strong>{entry.title}</strong>{entry.details && <small>{entry.details}</small>}{entry.source_reference && <em>{entry.source_reference}</em>}</td><td>{entry.faction_name}</td><td>V{entry.volume}</td><td><DeltaSummary entry={entry} /></td><td><VisibilityToggle compact value={entry.visibility} onChange={(visibility) => { void mutate(() => updateJournalVisibility(entry.id, visibility), "Visibilité modifiée.", (previous) => { previous.journal.find((item) => item.id === entry.id)!.visibility = visibility; return previous; }); }} /></td><td><button className="icon-button danger" onClick={() => window.confirm("Supprimer cette entrée et recalculer les totaux ?") && void mutate(() => deleteJournalEntry(entry.id), "Entrée supprimée.", (previous) => { previous.journal = previous.journal.filter((item) => item.id !== entry.id); const faction = previous.factions.find((f) => f.faction_id === entry.faction_id)!; faction.rp = Math.max(0, faction.rp - entry.rp_delta); faction.jf = Math.max(0, faction.jf - entry.jf_delta); faction.tension = Math.max(0, faction.tension - entry.tension_delta); return previous; })}><Trash2 size={16} /></button></td></tr>)}</tbody></table></div>
      {open && <div className="modal-backdrop"><form className="modal-card" onSubmit={submit}><div className="modal-head"><div><p className="eyebrow">Nouvelle variation</p><h3>Ajouter au journal</h3></div><button type="button" className="icon-button" onClick={() => setOpen(false)}><X /></button></div><div className="form-grid"><label>Faction<select value={form.faction_id} onChange={(e) => setForm({ ...form, faction_id: e.target.value })}>{data.factions.map((f) => <option key={f.faction_id} value={f.faction_id}>{f.short_name}</option>)}</select></label><label>Date<input type="date" value={form.occurred_on} onChange={(e) => setForm({ ...form, occurred_on: e.target.value })} /></label><label>Opération<select value={form.operation} onChange={(e) => setForm({ ...form, operation: e.target.value })}><option value="reputation_gain">Gain de réputation</option><option value="reputation_loss">Perte de réputation</option><option value="favor_spend">Dépense de faveurs</option><option value="tension_up">Hausse de tension</option><option value="tension_down">Réduction de tension</option></select></label><label>Valeur<input type="number" min="1" value={form.amount} onChange={(e) => setForm({ ...form, amount: Number(e.target.value) })} /></label><label>Volume<select value={form.volume} onChange={(e) => setForm({ ...form, volume: Number(e.target.value) })}>{[1,2,3,4,5,6].map((v) => <option key={v} value={v}>Volume {v}</option>)}</select></label><div className="visibility-form-field"><span>Visibilité</span><VisibilityToggle value={form.visibility} onChange={(visibility) => setForm({ ...form, visibility })} /></div><label className="span-2">Titre<input required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} placeholder="Ex. Crise de la ferme résolue" /></label><label className="span-2">Détails<textarea value={form.details} onChange={(e) => setForm({ ...form, details: e.target.value })} /></label><label className="span-2">Référence<input value={form.source_reference} onChange={(e) => setForm({ ...form, source_reference: e.target.value })} placeholder="Volume et page, si applicable" /></label></div><div className="modal-actions"><button type="button" className="button secondary" onClick={() => setOpen(false)}>Annuler</button><button className="button primary">Enregistrer</button></div></form></div>}
    </div>
  );
}

function JournalHub({ data, mutate, demo, onChanged, onNotice, onError }: { data: CampaignData; mutate: Mutate; demo: boolean; onChanged: () => Promise<void>; onNotice: (message: string) => void; onError: (message: string | null) => void }) {
  const [section, setSection] = useState<"reputation" | "notes" | "quest-journal">("reputation");
  return <div className="hub-stack"><div className="section-tabs" role="tablist" aria-label="Type de journal"><button role="tab" aria-selected={section === "reputation"} className={section === "reputation" ? "active" : ""} onClick={() => setSection("reputation")}>Réputation</button><button role="tab" aria-selected={section === "notes"} className={section === "notes" ? "active" : ""} onClick={() => setSection("notes")}>Carnet de notes</button><button role="tab" aria-selected={section === "quest-journal"} className={section === "quest-journal" ? "active" : ""} onClick={() => setSection("quest-journal")}>Journal de quête</button></div>{section === "reputation" && <JournalTab data={data} mutate={mutate} />}{section === "notes" && <QuestJournalTab campaignId={data.settings.campaign_id} entries={data.questEntries} factionHistory={data.journal.filter((entry) => entry.visibility === "players")} demo={demo} onChanged={onChanged} onNotice={onNotice} onError={onError} />}{section === "quest-journal" && <QuestWritingTab page={data.questJournalPage} revisions={data.questJournalRevisions} canRestoreHistory demo={demo} onChanged={onChanged} onNotice={onNotice} onError={onError} />}</div>;
}

function FactionsHub({ data, mutate }: { data: CampaignData; mutate: Mutate }) {
  const [section, setSection] = useState<"overview" | "services" | "politics">("overview");
  return <div className="hub-stack"><div className="section-tabs" role="tablist" aria-label="Registres des factions"><button role="tab" aria-selected={section === "overview"} className={section === "overview" ? "active" : ""} onClick={() => setSection("overview")}>Fiches</button><button role="tab" aria-selected={section === "services"} className={section === "services" ? "active" : ""} onClick={() => setSection("services")}>Services</button><button role="tab" aria-selected={section === "politics"} className={section === "politics" ? "active" : ""} onClick={() => setSection("politics")}>Politique</button></div>{section === "overview" && <FactionsTab data={data} mutate={mutate} />}{section === "services" && <ServicesTab data={data} mutate={mutate} />}{section === "politics" && <PoliticsTab data={data} mutate={mutate} />}</div>;
}

function ReferencesHub({ campaignId, demo, onNotice, onError }: { campaignId: string; demo: boolean; onNotice: (message: string) => void; onError: (message: string | null) => void }) {
  return <Suspense fallback={<LoadingScreen label="Ouverture des archives…" />}><ArchivesTab campaignId={campaignId} demo={demo} onNotice={onNotice} onError={onError} /></Suspense>;
}

function FactionsTab({ data, mutate }: { data: CampaignData; mutate: Mutate }) {
  const [selected, setSelected] = useState(data.factions[0].faction_id);
  const faction = data.factions.find((f) => f.faction_id === selected)!;
  const [draft, setDraft] = useState({ public_summary: faction.public_summary ?? "", gm_notes: faction.gm_notes ?? "", is_player_visible: faction.is_player_visible });
  useEffect(() => setDraft({ public_summary: faction.public_summary ?? "", gm_notes: faction.gm_notes ?? "", is_player_visible: faction.is_player_visible }), [faction.faction_id]);
  async function save(event: FormEvent) {
    event.preventDefault();
    const patch = { public_summary: draft.public_summary || null, gm_notes: draft.gm_notes || null, is_player_visible: draft.is_player_visible };
    await mutate(() => updateFactionDetails(data.settings.campaign_id, faction.faction_id, patch), "Fiche de faction enregistrée.", (previous) => { Object.assign(previous.factions.find((f) => f.faction_id === faction.faction_id)!, patch); return previous; });
  }
  return <div className="page-stack"><SectionHeading eyebrow="Six pouvoirs de Geb" title="Fiches de faction" /><div className="split-layout"><div className="selection-list">{data.factions.map((item) => <button key={item.faction_id} className={item.faction_id === selected ? "selected" : ""} onClick={() => setSelected(item.faction_id)} style={{ "--accent": item.accent } as React.CSSProperties}><span className="selection-dot" /><div><strong>{item.short_name}</strong><small>{item.status} · {item.rp} RP</small></div><ChevronRight size={17} /></button>)}</div><form className="panel detail-form" onSubmit={save}><div className="detail-hero" style={{ "--accent": faction.accent } as React.CSSProperties}><div className="faction-monogram large">{faction.short_name.slice(0, 2).toUpperCase()}</div><div><p className="eyebrow">{faction.domain}</p><h2>{faction.name}</h2><p>{faction.public_description}</p></div></div><div className="stat-strip"><div><span>Position</span><strong>{faction.status}</strong></div><div><span>Réputation</span><strong>{faction.rp} RP</strong></div><div><span>Faveurs</span><strong>{faction.jf} JF</strong></div><div><span>Tension</span><strong>{faction.tension_label}</strong></div></div><label className="toggle-row"><input type="checkbox" checked={draft.is_player_visible} onChange={(e) => setDraft({ ...draft, is_player_visible: e.target.checked })} /><span><strong>Afficher cette faction aux joueurs</strong><small>Masquer la fiche entière tant qu’elle n’est pas pertinente.</small></span></label><label>Résumé visible des joueurs<textarea value={draft.public_summary} onChange={(e) => setDraft({ ...draft, public_summary: e.target.value })} placeholder="Ce que les personnages savent de leur relation actuelle…" /></label><label>Notes privées du MJ<textarea value={draft.gm_notes} onChange={(e) => setDraft({ ...draft, gm_notes: e.target.value })} /></label><div className="form-footer"><span>{unlockedServices(faction.rp, faction.slug, data.settings)}</span><button className="button primary"><Save size={17} />Enregistrer</button></div></form></div></div>;
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
    await mutate(() => spendFavor({ campaignId: data.settings.campaign_id, factionId, title: requestTitle, cost: quote.cost, volume: data.settings.current_volume, visibility: "gm_only" }), "Dépense ajoutée au journal (MJ uniquement).", (previous) => { const target = previous.factions.find((f) => f.faction_id === factionId)!; target.jf -= quote.cost; previous.journal.unshift({ id: crypto.randomUUID(), campaign_id: previous.settings.campaign_id, faction_id: factionId, faction_name: target.short_name, occurred_on: new Date().toISOString().slice(0,10), volume: previous.settings.current_volume, title: requestTitle, details: "Service de faction accordé.", rp_delta: 0, jf_delta: -quote.cost, tension_delta: 0, visibility: "gm_only", source_reference: null }); return previous; });
    setTitle("");
  }
  return <div className="page-stack"><SectionHeading eyebrow="Réserve de faveurs" title="Planificateur de services" /><section className="service-planner panel"><div className="planner-controls"><label>Faction<select value={factionId} onChange={(e) => changeFaction(e.target.value)}>{data.factions.map((f) => <option key={f.faction_id} value={f.faction_id}>{f.short_name} — {f.jf} JF</option>)}</select></label><label>Service<select value={service.id} onChange={(e) => setServiceId(e.target.value)}>{services.map((s) => <option key={s.id} value={s.id}>{s.scale} · {s.domain}</option>)}</select></label><label>Avantage<select value={advantage} onChange={(e) => setAdvantage(e.target.value as typeof advantage)}><option value="none">Aucun</option><option value="first_liked">Premier service apprécié</option><option value="admired_discount">Réduction admirée</option></select></label><label>Objet de la demande<input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Pourquoi le groupe sollicite la faction" /></label></div><div className={`quote-card ${quote.allowed ? "allowed" : "blocked"}`}><span>{quote.allowed ? <Sparkles size={22} /> : <ShieldAlert size={22} />}</span><div><small>{quote.reason}</small><strong>{quote.cost} JF</strong><p>Solde après demande : {quote.balanceAfter} JF</p></div><button className="button primary" disabled={!quote.allowed} onClick={() => void confirmSpend()}>Accorder et journaliser</button></div></section><section className="service-reference-list">{services.map((item) => <article key={item.id} className="panel"><header><span className={`scale scale-${item.scale.toLowerCase()}`}>{item.scale}</span><strong>{item.required_rp} RP · {item.base_cost} JF</strong></header><h3>{item.domain}</h3><p>{item.examples}</p><small>{item.safeguard} · {item.frequency}</small></article>)}</section></div>;
}

function playerContactNotes(contact: Contact) {
  return [
    contact.player_character_notes && `Caractère et repères\n${contact.player_character_notes}`,
    contact.player_debt_notes && `Promesses et dettes\n${contact.player_debt_notes}`,
    contact.player_notes && `Notes libres\n${contact.player_notes}`,
  ].filter(Boolean).join("\n\n");
}

function emptyContact(campaignId: string, faction: FactionOverview): Contact {
  return { id: crypto.randomUUID(), campaign_id: campaignId, faction_id: faction.faction_id, faction_name: faction.short_name, name: "", first_name: null, last_name: null, role: "", public_description: null, image_path: null, avatar_x: 50, avatar_y: 50, avatar_zoom: 1, state: "À introduire", attitude: "Neutre", promise_debt: null, due_text: null, gm_notes: null, player_character_notes: null, player_debt_notes: null, player_notes: null, visibility: "gm_only", is_primary: false };
}

function portraitSource(contact: Contact | null, preview: string | null = null) {
  return preview ?? contactPortraitUrl(contact?.image_path ?? null);
}

function portraitCropStyle(contact: Pick<Contact, "avatar_x" | "avatar_y" | "avatar_zoom">): React.CSSProperties {
  const zoom = contact.avatar_zoom ?? 1;
  const x = contact.avatar_x ?? 50;
  const y = contact.avatar_y ?? 50;
  return {
    objectPosition: "50% 50%",
    transform: `translate(${(50 - x) * (zoom - 1)}%, ${(50 - y) * (zoom - 1)}%) scale(${zoom})`,
  };
}

function contactIdentity(contact: Pick<Contact, "name" | "first_name" | "last_name">) {
  const pieces = contact.name.trim().split(/\s+/).filter(Boolean);
  return {
    first_name: contact.first_name ?? pieces[0] ?? "",
    last_name: contact.last_name ?? pieces.slice(1).join(" "),
  };
}

function ContactsTab({ data, mutate, demo }: { data: CampaignData; mutate: Mutate; demo: boolean }) {
  const [selected, setSelected] = useState<Contact | null>(null);
  const [showPrepared, setShowPrepared] = useState(false);
  const [portraitFile, setPortraitFile] = useState<File | null>(null);
  const [portraitPreview, setPortraitPreview] = useState<string | null>(null);
  const [portraitError, setPortraitError] = useState<string | null>(null);
  const grouped = data.factions
    .map((faction) => ({ faction, contacts: data.contacts.filter((contact) => contact.faction_id === faction.faction_id && (showPrepared || contact.state !== "À introduire")) }))
    .filter(({ contacts }) => contacts.length > 0 || showPrepared);

  useEffect(() => () => {
    if (portraitPreview?.startsWith("blob:")) URL.revokeObjectURL(portraitPreview);
  }, [portraitPreview]);

  function closeEditor() {
    setSelected(null);
    setPortraitFile(null);
    setPortraitPreview(null);
    setPortraitError(null);
  }

  function openContact(contact: Contact | null, faction?: FactionOverview) {
    const owner = faction ?? data.factions.find((item) => item.faction_id === contact?.faction_id);
    if (!owner) return;
    const copy = contact ? structuredClone(contact) : null;
    setSelected(copy ? { ...emptyContact(data.settings.campaign_id, owner), ...copy, ...contactIdentity(copy) } : emptyContact(data.settings.campaign_id, owner));
    setPortraitFile(null);
    setPortraitPreview(null);
    setPortraitError(null);
  }

  function choosePortrait(file: File | null) {
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      setPortraitError("Choisissez un fichier image.");
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      setPortraitError("L’image ne doit pas dépasser 5 Mo.");
      return;
    }
    if (portraitPreview?.startsWith("blob:")) URL.revokeObjectURL(portraitPreview);
    setPortraitFile(file);
    setPortraitPreview(URL.createObjectURL(file));
    setPortraitError(null);
  }

  async function save(event: FormEvent) {
    event.preventDefault();
    if (!selected) return;
    const firstName = selected.first_name?.trim() ?? "";
    const lastName = selected.last_name?.trim() ?? "";
    const displayName = [firstName, lastName].filter(Boolean).join(" ");
    if (!displayName) {
      setPortraitError("Indiquez au moins le prénom du contact.");
      return;
    }
    const original = data.contacts.find((contact) => contact.id === selected.id);
    let imagePath = selected.image_path;
    try {
      if (portraitFile) imagePath = demo ? portraitPreview : await uploadContactPortrait(data.settings.campaign_id, portraitFile);
      const saved: Contact = {
        ...selected,
        name: displayName,
        first_name: firstName,
        last_name: lastName || null,
        role: selected.role.trim(),
        public_description: selected.public_description?.trim() || null,
        image_path: imagePath,
      };
      const succeeded = await mutate(
        () => saveContact(saved),
        original ? "Contact enregistré." : "Contact ajouté.",
        (previous) => {
          const index = previous.contacts.findIndex((contact) => contact.id === saved.id);
          if (index >= 0) previous.contacts[index] = saved;
          else previous.contacts.push(saved);
          return previous;
        },
      );
      if (succeeded && !demo && original?.image_path && original.image_path !== imagePath) await deleteContactPortrait(original.image_path);
      if (succeeded) closeEditor();
    } catch (caught) {
      setPortraitError(caught instanceof Error ? caught.message : "Enregistrement du portrait impossible.");
    }
  }

  return <div className="page-stack">
    <SectionHeading
      eyebrow="Personnes connues"
      title="Contacts des factions"
      actions={<button className="button secondary tiny" onClick={() => setShowPrepared((value) => !value)}>{showPrepared ? "Masquer les préparés" : "Voir les contacts préparés"}</button>}
    />
    <div className="contact-grid">
      {grouped.map(({ faction, contacts }) => <section className="panel contact-group" key={faction.faction_id} style={{ "--accent": faction.accent } as React.CSSProperties}>
        <div className="contact-group-title">
          <span className="selection-dot" />
          <div><h3>{faction.short_name}</h3><small>{contacts.length} contact{contacts.length > 1 ? "s" : ""}</small></div>
          <button className="icon-button" type="button" onClick={() => openContact(null, faction)} aria-label={`Ajouter un contact aux ${faction.short_name}`}><Plus /></button>
        </div>
        {contacts.map((contact) => <button className="contact-row" key={contact.id} onClick={() => openContact(contact)}>
          <div><strong>{contact.name}</strong><small>{contact.role || "Rôle à préciser"}</small></div>
          <div><VisibilityBadge visibility={contact.visibility} /><span>{contact.state}</span></div>
        </button>)}
      </section>)}
      {grouped.length === 0 && <EmptyState title="Aucun contact actif">Les contacts préparés restent disponibles via le bouton ci-dessus.</EmptyState>}
    </div>
    {selected && <div className="modal-backdrop">
      <form className="modal-card wide contact-editor" onSubmit={save}>
        <div className="modal-head">
          <div><p className="eyebrow">{selected.faction_name}</p><h3>{[selected.first_name, selected.last_name].filter(Boolean).join(" ") || "Nouveau contact"}</h3></div>
          <button type="button" className="icon-button" onClick={closeEditor} aria-label="Fermer"><X /></button>
        </div>
        <div className="contact-editor-grid">
          <div className="contact-portrait-upload">
            <span>Image du contact</span>
            <div className="contact-portrait-crop-preview">
              {portraitSource(selected, portraitPreview)
                ? <img src={portraitSource(selected, portraitPreview)!} alt="Aperçu de l’image du contact" style={portraitCropStyle(selected)} />
                : <ImagePlus size={30} />}
            </div>
            <label className="button secondary tiny upload-control"><input type="file" accept="image/jpeg,image/png,image/webp,image/gif" onChange={(event) => choosePortrait(event.target.files?.[0] ?? null)} />Choisir ou remplacer l’image</label>
            {(selected.image_path || portraitFile) && <button type="button" className="text-button danger-text" onClick={() => { setSelected({ ...selected, image_path: null }); setPortraitFile(null); setPortraitPreview(null); }}>Retirer l’image</button>}
            <div className="contact-crop-controls">
              <strong>Jeton affiché aux joueurs</strong>
              <label>Zoom<input type="range" min="1" max="2.5" step="0.05" value={selected.avatar_zoom} onChange={(event) => setSelected({ ...selected, avatar_zoom: Number(event.target.value) })} /></label>
              <label>Centrage horizontal<input type="range" min="0" max="100" value={selected.avatar_x} onChange={(event) => setSelected({ ...selected, avatar_x: Number(event.target.value) })} /></label>
              <label>Centrage vertical<input type="range" min="0" max="100" value={selected.avatar_y} onChange={(event) => setSelected({ ...selected, avatar_y: Number(event.target.value) })} /></label>
              <button type="button" className="text-button" onClick={() => setSelected({ ...selected, avatar_x: 50, avatar_y: 50, avatar_zoom: 1 })}>Réinitialiser le cadrage</button>
            </div>
            <small>JPEG, PNG, WebP ou GIF · 5 Mo maximum.</small>
            {portraitError && <p className="form-error">{portraitError}</p>}
          </div>
          <div className="form-grid contact-editor-fields">
            <label>Prénom<input required value={selected.first_name ?? ""} onChange={(event) => setSelected({ ...selected, first_name: event.target.value })} /></label>
            <label>Nom<input value={selected.last_name ?? ""} onChange={(event) => setSelected({ ...selected, last_name: event.target.value })} /></label>
            <label className="span-2">Rôle / Profession<input value={selected.role} onChange={(event) => setSelected({ ...selected, role: event.target.value })} placeholder="Ex. Main-d’œuvre et nécromancie" /></label>
            <label>État / Situation<select value={selected.state} onChange={(event) => setSelected({ ...selected, state: event.target.value })}>{["À introduire", "Actif", "Distant", "Compromis", "Hostile", "Indisponible"].map((value) => <option key={value}>{value}</option>)}</select></label>
            <label>Attitude<input value={selected.attitude} onChange={(event) => setSelected({ ...selected, attitude: event.target.value })} /></label>
            <label>Visibilité<select value={selected.visibility} onChange={(event) => setSelected({ ...selected, visibility: event.target.value as Visibility })}><option value="gm_only">MJ uniquement</option><option value="players">Visible joueurs</option></select></label>
            <label className="check-label"><input type="checkbox" checked={selected.is_primary} onChange={(event) => setSelected({ ...selected, is_primary: event.target.checked })} />Contact principal</label>
            <label className="span-2">Description fixe<textarea value={selected.public_description ?? ""} onChange={(event) => setSelected({ ...selected, public_description: event.target.value || null })} placeholder="Description approfondie du PNJ, visible par les joueurs mais modifiable uniquement par le MJ." /></label>
            <label className="span-2">Notes partagées des joueurs<textarea readOnly value={playerContactNotes(selected)} placeholder="Les notes prises par les joueurs apparaîtront ici." /></label>
            <label className="span-2">Notes privées du MJ<textarea value={selected.gm_notes ?? ""} onChange={(event) => setSelected({ ...selected, gm_notes: event.target.value || null })} /></label>
          </div>
        </div>
        <div className="modal-actions"><button type="button" className="button secondary" onClick={closeEditor}>Annuler</button><button className="button primary">Enregistrer</button></div>
      </form>
    </div>}
  </div>;
}

function PoliticsTab({ data, mutate }: { data: CampaignData; mutate: Mutate }) {
  const [selected, setSelected] = useState<Relationship | null>(null);
  const [draft, setDraft] = useState<{ headline: string; detail: string; color: RelationshipColor; visibility: Visibility } | null>(null);
  const [dossier, setDossier] = useState(data.dossiers[0]?.id ?? "");
  const [showMatrix, setShowMatrix] = useState(false);
  const selectedDossier = data.dossiers.find((item) => item.id === dossier);
  function relation(source: FactionOverview, target: FactionOverview) { return data.relationships.find((item) => item.source_faction_id === source.faction_id && item.target_faction_id === target.faction_id); }
  function factionShortName(factionId: string) { return data.factions.find((item) => item.faction_id === factionId)?.short_name ?? "Faction inconnue"; }
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
      <div className="politics-compact-head"><p>Consultez un dossier lorsque la relation devient pertinente dans la partie.</p><button type="button" className="button secondary tiny" onClick={() => setShowMatrix((value) => !value)}>{showMatrix ? "Masquer la matrice complète" : "Afficher la matrice complète"}</button></div>
      {showMatrix && <><div className="legend-row color-legend">
        <span><i className="tone-dot favorable" />Favorable</span>
        <span><i className="tone-dot uncertain" />Tendue ou ambiguë</span>
        <span><i className="tone-dot hostile" />Hostile</span>
      </div>
      <div className="matrix-wrap">
        <table className="politics-matrix">
          <thead><tr><th>Point de vue ↓</th>{data.factions.map((f) => <th key={f.faction_id}>{f.short_name}</th>)}</tr></thead>
          <tbody>{data.factions.map((source) => <tr key={source.faction_id}><th>{source.short_name}</th>{data.factions.map((target) => {
            const item = relation(source, target);
            return <td key={target.faction_id} className={!item ? "diagonal" : item.color}><button disabled={!item} onClick={() => item && openRelationship(item)}>{item ? <><strong>{item.headline}</strong><span>{item.visibility === "players" ? <Eye size={14} /> : <EyeOff size={14} />}</span></> : "—"}</button></td>;
          })}</tr>)}</tbody>
        </table>
      </div></>}
      <section className="dossier-section">
        <div className="dossier-picker"><p className="eyebrow">15 dossiers bilatéraux</p><select value={dossier} onChange={(e) => setDossier(e.target.value)}>{data.dossiers.map((item) => <option key={item.id} value={item.id}>{item.pair_name}</option>)}</select></div>
        {selectedDossier && <article className="dossier-card"><div className="dossier-core"><span>Noyau canon</span><p>{selectedDossier.canon_core}</p></div><div className="dossier-directions"><div><span>{factionShortName(selectedDossier.faction_a_id)} → {factionShortName(selectedDossier.faction_b_id)}</span><p>{selectedDossier.a_to_b}</p></div><div><span>{factionShortName(selectedDossier.faction_b_id)} → {factionShortName(selectedDossier.faction_a_id)}</span><p>{selectedDossier.b_to_a}</p></div></div><div className="dossier-grid"><div><span>Intérêt commun</span><p>{selectedDossier.common_interest}</p></div><div><span>Ligne de fracture</span><p>{selectedDossier.fracture}</p></div></div></article>}
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
          <div className="reveal-actions"><button type="button" className={draft.visibility === "gm_only" ? "active" : ""} onClick={() => setDraft((current) => current ? { ...current, visibility: "gm_only" } : current)}><EyeOff />MJ uniquement</button><button type="button" className={draft.visibility === "players" ? "active" : ""} onClick={() => setDraft((current) => current ? { ...current, visibility: "players" } : current)}><Eye />Visible joueurs</button></div>
          <div className="modal-actions"><button type="button" className="button secondary" onClick={closeRelationship}>Annuler</button><button className="button primary"><Save size={17} />Enregistrer</button></div>
        </form>
      </div>}
    </div>
  );
}

function ProgressionTab({ data, mutate, demo }: { data: CampaignData; mutate: Mutate; demo: boolean }) {
  const campaignVolumeGuides = [
    { title: "Volume 1", stakes: "Événements, choix et découvertes à suivre.", factions: "Factions concernées par la campagne" },
    { title: "Volume 2", stakes: "Événements, choix et découvertes à suivre.", factions: "Factions concernées par la campagne" },
    { title: "Volume 3", stakes: "Événements, choix et découvertes à suivre.", factions: "Factions concernées par la campagne" },
    { title: "Volume 4", stakes: "Événements, choix et découvertes à suivre.", factions: "Factions concernées par la campagne" },
    { title: "Volume 5", stakes: "Événements, choix et découvertes à suivre.", factions: "Factions concernées par la campagne" },
    { title: "Volume 6", stakes: "Événements, choix et découvertes à suivre.", factions: "Factions concernées par la campagne" },
  ];
  const volumeGuides = campaignVolumeGuides;
  const [selectedVolume, setSelectedVolume] = useState(data.settings.current_volume);
  const [showRoadmap, setShowRoadmap] = useState(false);
  const [selected, setSelected] = useState<Milestone | null>(null);
  const visible = data.milestones.filter((item) => item.volume === selectedVolume);
  const count = (volume: number, status: MilestoneStatus) => data.milestones.filter((item) => item.volume === volume && item.status === status).length;

  return <div className="page-stack">
    <SectionHeading eyebrow="Volume en cours" title="Jalons de campagne" actions={<button type="button" className="button secondary tiny" onClick={() => setShowRoadmap((value) => !value)}>{showRoadmap ? "Masquer la feuille de route" : "Consulter les autres volumes"}</button>} />
    <section className="volume-track" aria-label="Filtrer les jalons par volume">{volumeGuides.filter((_guide, index) => showRoadmap || index + 1 === data.settings.current_volume).map((guide) => {
      const volume = showRoadmap ? volumeGuides.indexOf(guide) + 1 : data.settings.current_volume;
      const total = data.milestones.filter((item) => item.volume === volume).length;
      const resolved = count(volume, "succeeded") + count(volume, "missed") + count(volume, "excluded");
      return <button type="button" key={volume} className={`${selectedVolume === volume ? "selected" : ""} ${data.settings.current_volume === volume ? "current" : ""}`} onClick={() => setSelectedVolume(volume)}>
        <span>{volume}</span><div><strong>Volume {volume}</strong><em>{guide.title}</em><p>{guide.stakes}</p><small>{guide.factions}</small><footer>{resolved}/{total} jalons classés{data.settings.current_volume === volume && <i>Volume actuel</i>}</footer></div>
      </button>;
    })}</section>
    <div className="progression-heading"><SectionHeading eyebrow="Récompenses officielles vérifiées" title={`Jalons du volume ${selectedVolume}`} /><div className="status-legend"><span className="milestone-status succeeded">Réussi</span><span className="milestone-status missed">Manqué</span><span className="milestone-status excluded">Écarté</span><span className="milestone-status pending">En attente</span></div></div>
    <div className="table-wrap"><table className="data-table milestone-table"><thead><tr><th>Chapitre</th><th>Jalon</th><th>Effets prévus</th><th>Condition</th><th>État</th></tr></thead><tbody>{visible.map((item) => <tr key={item.id} className={`milestone-row ${item.status}`}><td>{item.chapter ?? "—"}</td><td><strong>{item.title}</strong><small>{item.source_reference}</small>{item.resolution_note && <em>Note : {item.resolution_note}</em>}</td><td>{describeEffects(item.reward_effects, data)}</td><td>{item.condition}</td><td><span className={`milestone-status ${item.status}`}>{statusLabel(item.status)}</span>{item.status === "excluded" && item.excluded_by_title && <small>par « {item.excluded_by_title} »</small>}<button className="button tiny secondary" onClick={() => setSelected(item)}>{item.status === "pending" ? "Résoudre" : item.status === "excluded" ? "Choisir plutôt" : "Modifier"}</button></td></tr>)}</tbody></table></div>
    <p className="footnote">Changer de carte filtre uniquement cette liste : le volume actuel de la campagne reste inchangé. Un choix réussi écarte automatiquement ses alternatives ; le modifier annule proprement ses effets dans le journal.</p>
    {selected && <MilestoneResolutionModal item={selected} data={data} mutate={mutate} demo={demo} onClose={() => setSelected(null)} />}
  </div>;
}

type EffectDraft = { key: string; label: string; faction_id: string; amount: number; min: number; max: number; locked: boolean; scope?: MilestoneEffectTemplate["scope"]; distinct_group?: string; exclude_faction_ids?: string[] };

function statusLabel(status: MilestoneStatus) {
  return { pending: "En attente", succeeded: "Réussi", missed: "Manqué", excluded: "Écarté" }[status];
}

function factionName(data: CampaignData, factionId: string) {
  return data.factions.find((faction) => faction.faction_id === factionId)?.short_name ?? "Faction";
}

function isConvoyeurs(faction: FactionOverview) { return faction.slug === "charretiers" || faction.short_name === "Convoyeurs"; }

function signed(value: number) { return value > 0 ? `+${value}` : String(value); }

function describeEffects(effects: MilestoneEffectTemplate[], data: CampaignData) {
  if (!effects?.length) return "Aucun effet automatique";
  return effects.map((effect) => {
    const range = effect.amount !== undefined ? signed(effect.amount) : `${signed(effect.amount_min ?? 0)} à ${signed(effect.amount_max ?? 0)}`;
    if (effect.scope === "all_great") return `Toutes les Grandes Factions ${range}`;
    if (effect.scope === "transfer_carters") return "Transfert intégral des RP des Convoyeurs";
    if (effect.faction_ids) return `${effect.faction_ids.map((id) => factionName(data, id)).join(" et ")} ${range}`;
    return `${effect.faction_id ? factionName(data, effect.faction_id) : effect.label} ${range}`;
  }).join(" · ");
}

function draftEffects(item: Milestone, data: CampaignData): EffectDraft[] {
  const previous = item.resolved_effects ?? [];
  let previousIndex = 0;
  const drafts: EffectDraft[] = [];
  item.reward_effects.forEach((template, templateIndex) => {
    const ids = template.faction_ids ?? (template.scope === "all_great" ? data.factions.filter((faction) => !isConvoyeurs(faction)).map((faction) => faction.faction_id) : [template.faction_id ?? ""]);
    if (template.scope === "transfer_carters") {
      const carters = data.factions.find(isConvoyeurs);
      const target = previous.find((effect) => effect.amount > 0);
      drafts.push({ key: `${templateIndex}-transfer`, label: template.label, faction_id: target?.faction_id ?? data.factions.find((faction) => !isConvoyeurs(faction))?.faction_id ?? "", amount: target?.amount ?? carters?.rp ?? 0, min: 0, max: 999, locked: false, scope: template.scope, exclude_faction_ids: carters ? [carters.faction_id] : [] });
      return;
    }
    ids.forEach((id, idIndex) => {
      const resolved = previous[previousIndex++];
      drafts.push({
        key: `${templateIndex}-${idIndex}`,
        label: ids.length > 1 ? factionName(data, id) : template.label,
        faction_id: resolved?.faction_id ?? id,
        amount: resolved?.amount ?? template.amount ?? template.amount_min ?? 0,
        min: template.amount ?? template.amount_min ?? -999,
        max: template.amount ?? template.amount_max ?? 999,
        locked: Boolean(template.faction_id || template.faction_ids || template.scope === "all_great"),
        scope: template.scope,
        distinct_group: template.distinct_group,
        exclude_faction_ids: template.exclude_faction_ids,
      });
    });
  });
  return drafts;
}

function MilestoneResolutionModal({ item, data, mutate, demo, onClose }: { item: Milestone; data: CampaignData; mutate: Mutate; demo: boolean; onClose: () => void }) {
  const initialOutcome = item.status === "missed" ? "missed" : "succeeded";
  const [outcome, setOutcome] = useState<"succeeded" | "missed">(initialOutcome);
  const [note, setNote] = useState(item.resolution_note ?? "");
  const [effects, setEffects] = useState(() => draftEffects(item, data));
  const [validation, setValidation] = useState<string | null>(null);
  const eligibleFactions = (effect: EffectDraft) => data.factions.filter((faction) => !effect.exclude_faction_ids?.includes(faction.faction_id) && (effect.scope !== "any_great" || !isConvoyeurs(faction)));
  const setEffect = (key: string, patch: Partial<EffectDraft>) => setEffects((current) => current.map((effect) => effect.key === key ? { ...effect, ...patch } : effect));

  function resolvedEffects(): MilestoneEffect[] {
    const duplicateGroups = effects.filter((effect) => effect.distinct_group).reduce<Record<string, string[]>>((groups, effect) => ({ ...groups, [effect.distinct_group!]: [...(groups[effect.distinct_group!] ?? []), effect.faction_id] }), {});
    if (Object.values(duplicateGroups).some((ids) => new Set(ids).size !== ids.length)) throw new Error("Choisissez une faction différente pour chaque récompense de cette série.");
    const result: MilestoneEffect[] = [];
    effects.forEach((effect) => {
      if (!effect.faction_id) throw new Error("Chaque récompense doit désigner une faction.");
      if (effect.amount < effect.min || effect.amount > effect.max) throw new Error(`Le montant de « ${effect.label} » doit être compris entre ${effect.min} et ${effect.max}.`);
      if (effect.scope === "transfer_carters") {
        const carters = data.factions.find(isConvoyeurs);
        if (!carters) throw new Error("Le Consortium des Convoyeurs est introuvable.");
        result.push({ label: "Convoyeurs — transfert", faction_id: carters.faction_id, amount: -Math.abs(effect.amount), jf_amount: 0 });
        result.push({ label: effect.label, faction_id: effect.faction_id, amount: Math.abs(effect.amount), jf_amount: 0 });
      } else result.push({ label: effect.label, faction_id: effect.faction_id, amount: effect.amount });
    });
    return result;
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setValidation(null);
    let resolved: MilestoneEffect[] | null = null;
    try { if (outcome === "succeeded") resolved = resolvedEffects(); } catch (caught) { setValidation(caught instanceof Error ? caught.message : "Récompense invalide."); return; }
    const saved = await mutate(
      () => resolveMilestone(item.id, outcome, note.trim() || null, resolved),
      outcome === "succeeded" ? "Jalon réussi et journal recalculé." : "Jalon classé comme manqué, sans gain de réputation.",
      (previous) => applyLocalMilestoneResolution(previous, item.id, outcome, note.trim() || null, resolved),
    );
    if (saved) onClose();
  }

  async function reopen() {
    const saved = await mutate(() => resolveMilestone(item.id, "pending", null, null), "Jalon remis en attente.", (previous) => applyLocalMilestoneResolution(previous, item.id, "pending", null, null));
    if (saved) onClose();
  }

  return <div className="modal-backdrop"><form className="modal-card wide milestone-modal" onSubmit={submit}>
    <div className="modal-head"><div><p className="eyebrow">Volume {item.volume} · {item.chapter}</p><h3>{item.title}</h3></div><button type="button" className="icon-button" onClick={onClose}><X /></button></div>
    {item.status === "excluded" && <p className="choice-warning">Ce choix est actuellement écarté par « {item.excluded_by_title} ». Le réussir remplacera automatiquement ce choix et annulera ses effets.</p>}
    <fieldset className="outcome-picker"><legend>Issue du jalon</legend><button type="button" className={outcome === "succeeded" ? "active succeeded" : ""} onClick={() => setOutcome("succeeded")}><strong>Réussi</strong><small>Appliquer les gains et pertes au journal</small></button><button type="button" className={outcome === "missed" ? "active missed" : ""} onClick={() => setOutcome("missed")}><strong>Manqué</strong><small>Classer le jalon sans distribuer de points</small></button></fieldset>
    {outcome === "succeeded" && <section className="reward-editor"><div><p className="eyebrow">Effets à appliquer</p><small>Les valeurs fixes sont verrouillées ; les choix et fourchettes viennent directement du livre.</small></div>{effects.map((effect) => <div className="reward-row" key={effect.key}><label><span>{effect.label}</span><select value={effect.faction_id} disabled={effect.locked} onChange={(event) => setEffect(effect.key, { faction_id: event.target.value })}>{eligibleFactions(effect).map((faction) => <option key={faction.faction_id} value={faction.faction_id}>{faction.short_name}</option>)}</select></label><label><span>RP</span><input type="number" value={effect.amount} min={effect.min} max={effect.max} disabled={effect.min === effect.max || effect.scope === "transfer_carters"} onChange={(event) => setEffect(effect.key, { amount: Number(event.target.value) })} /></label>{effect.min !== effect.max && <small>Valeur permise : {effect.min} à {effect.max}</small>}</div>)}</section>}
    <label className="milestone-note"><span>Détails ou raison {outcome === "missed" ? "de l’échec" : "du résultat"} <small>(facultatif)</small></span><textarea value={note} onChange={(event) => setNote(event.target.value)} placeholder={outcome === "missed" ? (demo ? "Ex. Le groupe a choisi une autre solution…" : "Ex. Les PJ ont confié Altinmered à une tierce personne…") : "Une précision propre à cette campagne…"} /></label>
    {validation && <p className="form-error">{validation}</p>}
    <div className="modal-actions">{(item.status === "succeeded" || item.status === "missed") && <button type="button" className="button ghost danger" onClick={() => void reopen()}>Remettre en attente</button>}<span className="modal-spacer" /><button type="button" className="button secondary" onClick={onClose}>Annuler</button><button className="button primary">Enregistrer l’issue</button></div>
  </form></div>;
}

function applyLocalMilestoneResolution(previous: CampaignData, milestoneId: string, outcome: Exclude<MilestoneStatus, "excluded">, note: string | null, effects: MilestoneEffect[] | null) {
  const item = previous.milestones.find((milestone) => milestone.id === milestoneId)!;
  const undo = (id: string) => {
    previous.journal.filter((entry) => entry.milestone_id === id).forEach((entry) => {
      const faction = previous.factions.find((candidate) => candidate.faction_id === entry.faction_id);
      if (faction) { faction.rp = Math.max(0, faction.rp - entry.rp_delta); faction.jf = Math.max(0, faction.jf - entry.jf_delta); }
    });
    previous.journal = previous.journal.filter((entry) => entry.milestone_id !== id);
  };
  const restoreExcluded = (winnerId: string) => previous.milestones.filter((milestone) => milestone.excluded_by_milestone_id === winnerId).forEach((milestone) => { milestone.status = milestone.status_before_exclusion ?? "pending"; milestone.status_before_exclusion = null; milestone.excluded_by_milestone_id = null; milestone.excluded_by_title = null; });
  undo(item.id);
  restoreExcluded(item.id);
  if (outcome === "succeeded" && item.choice_group) {
    previous.milestones.filter((milestone) => milestone.choice_group === item.choice_group && milestone.id !== item.id && milestone.status === "succeeded").forEach((winner) => { undo(winner.id); restoreExcluded(winner.id); Object.assign(winner, { status: "pending", applied: false, applied_at: null, resolved_at: null, resolved_effects: null, resolution_note: null }); });
    previous.milestones.filter((milestone) => milestone.choice_group === item.choice_group && milestone.id !== item.id).forEach((sibling) => { sibling.status_before_exclusion = sibling.status === "excluded" ? sibling.status_before_exclusion ?? "pending" : sibling.status; sibling.status = "excluded"; sibling.excluded_by_milestone_id = item.id; sibling.excluded_by_title = item.title; sibling.applied = false; });
  }
  if (outcome === "succeeded") (effects ?? []).forEach((effect) => {
    const faction = previous.factions.find((candidate) => candidate.faction_id === effect.faction_id)!;
    const jf = effect.jf_amount ?? Math.max(effect.amount, 0);
    faction.rp = Math.max(0, faction.rp + effect.amount);
    faction.jf = Math.max(0, Math.min(previous.settings.jf_cap, faction.jf + jf));
    previous.journal.unshift({ id: crypto.randomUUID(), campaign_id: previous.settings.campaign_id, faction_id: effect.faction_id, faction_name: faction.short_name, occurred_on: new Date().toISOString().slice(0, 10), volume: item.volume, title: `${item.title} — ${effect.amount < 0 ? "perte" : "gain"}`, details: note ?? item.condition, rp_delta: effect.amount, jf_delta: jf, tension_delta: 0, visibility: "gm_only", source_reference: item.source_reference, milestone_id: item.id });
  });
  Object.assign(item, { status: outcome, applied: outcome === "succeeded", resolution_note: note, resolved_effects: outcome === "succeeded" ? effects : null, resolved_at: outcome === "pending" ? null : new Date().toISOString(), excluded_by_milestone_id: null, excluded_by_title: null, status_before_exclusion: null });
  return previous;
}

function SettingsTab({ data, mutate, campaignId }: { data: CampaignData; mutate: Mutate; campaignId: string }) {
  const [draft, setDraft] = useState({ ...data.settings });
  async function submit(event: FormEvent) { event.preventDefault(); await mutate(() => updateSettings(draft), "Configuration enregistrée.", (previous) => { previous.settings = draft; return previous; }); }
  const numeric = (key: keyof CampaignSettings, label: string, help: string, min = 0, max?: number) => <label className="setting-row"><span><strong>{label}</strong><small>{help}</small></span><input type="number" min={min} max={max} value={draft[key] as number} onChange={(e) => setDraft({ ...draft, [key]: Number(e.target.value) })} /></label>;
  return <div className="page-stack"><SectionHeading eyebrow="Paramètres de la maison" title="Règles du système" /><form className="settings-layout" onSubmit={submit}><section className="panel settings-panel"><h3>Progression</h3><label className="setting-row"><span><strong>Volume actuel</strong><small>Utilisé par défaut dans le journal et les demandes.</small></span><select value={draft.current_volume} onChange={(e) => setDraft({ ...draft, current_volume: Number(e.target.value) })}>{[1,2,3,4,5,6].map((v) => <option key={v} value={v}>Volume {v}</option>)}</select></label>{numeric("liked_threshold", "Seuil Apprécié", "Débloque les demandes mineures.")}{numeric("admired_threshold", "Seuil Admiré", "Débloque les demandes modérées.")}{numeric("revered_threshold", "Seuil Révéré", "Débloque les demandes majeures.")}{numeric("carters_major_threshold", "Majeure des Convoyeurs", "Seuil spécial, une fois dans la campagne.")}</section><section className="panel settings-panel"><h3>Faveurs</h3>{numeric("jf_cap", "Plafond souple de JF", "L’excédent doit être converti en avantage nommé.")}{numeric("minor_cost", "Demande mineure", "Coût de base en JF.")}{numeric("moderate_cost", "Demande modérée", "Coût de base en JF.")}{numeric("major_cost", "Demande majeure", "Coût de base en JF.")}{numeric("admired_discount", "Réduction admirée", "Première demande modérée du volume.")}</section><section className="panel settings-panel"><h3>Tension et vue joueurs</h3>{numeric("tension_max", "Tension maximale", "À ce niveau, la relation est rompue.", 1)}{numeric("tension_surcharge_level", "Niveau de surcharge", "Ajoute un coût aux demandes.")}{numeric("tension_surcharge", "Surcharge en JF", "Coût ajouté au niveau défini.")}<label className="toggle-row"><input type="checkbox" checked={draft.show_numeric_tension} onChange={(e) => setDraft({ ...draft, show_numeric_tension: e.target.checked })} /><span><strong>Afficher la tension chiffrée</strong><small>Ignoré en mode intuitif : les joueurs y voient toujours une formulation narrative.</small></span></label><fieldset className="display-mode-picker"><legend>Affichage de la vue joueurs</legend><label className={draft.player_display_mode === "numeric" ? "active" : ""}><input type="radio" name="player_display_mode" value="numeric" checked={draft.player_display_mode === "numeric"} onChange={() => setDraft({ ...draft, player_display_mode: "numeric" })} /><span><strong>Chiffrés</strong><small>RP, JF, coûts et seuils visibles.</small></span></label><label className={draft.player_display_mode === "intuitive" ? "active" : ""}><input type="radio" name="player_display_mode" value="intuitive" checked={draft.player_display_mode === "intuitive"} onChange={() => setDraft({ ...draft, player_display_mode: "intuitive" })} /><span><strong>Intuitif</strong><small>Uniquement des termes narratifs et les services actuellement possibles.</small></span></label></fieldset></section><div className="settings-submit"><p>Les modifications s’appliquent immédiatement aux calculs, sans réécrire le journal.</p><button className="button primary"><Save size={17} />Enregistrer les réglages</button></div></form><CampaignAccessPanel campaignId={campaignId} /></div>;
}

function CampaignAccessPanel({ campaignId }: { campaignId: string }) {
  const [members, setMembers] = useState<CampaignMember[]>([]);
  const [invites, setInvites] = useState<CampaignInvite[]>([]);
  const [pages, setPages] = useState<CampaignPlayerPage[]>([]);
  const [openedPage, setOpenedPage] = useState<CampaignPlayerPage | null>(null);
  const [expiresOn, setExpiresOn] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const refresh = useCallback(async () => { try { const [nextMembers, nextInvites, nextPages] = await Promise.all([listCampaignMembers(campaignId), listCampaignInvites(campaignId), listCampaignPlayerPages(campaignId)]); setMembers(nextMembers); setInvites(nextInvites); setPages(nextPages); setError(null); } catch (caught) { setError(caught instanceof Error ? caught.message : "Gestion de campagne indisponible."); } }, [campaignId]);
  useEffect(() => { void refresh(); }, [refresh]);
  const link = (invite: CampaignInvite) => `${window.location.origin}/join/${invite.token}`;
  async function create() { try { const expiresAt = expiresOn ? new Date(`${expiresOn}T23:59:59`).toISOString() : null; const invite = await createCampaignInvite(campaignId, expiresAt); setInvites((current) => [invite, ...current]); setNotice("Invitation créée."); } catch (caught) { setError(caught instanceof Error ? caught.message : "Création impossible."); } }
  async function copy(invite: CampaignInvite) { try { await navigator.clipboard.writeText(link(invite)); setNotice("Lien copié."); } catch { setError("Copie impossible : sélectionnez le lien dans votre navigateur."); } }
  async function revoke(invite: CampaignInvite) { try { await revokeCampaignInvite(invite.id); await refresh(); setNotice("Invitation révoquée."); } catch (caught) { setError(caught instanceof Error ? caught.message : "Révocation impossible."); } }
  async function remove(member: CampaignMember) { if (!window.confirm(`Retirer ${member.display_name} de la campagne ? Sa page personnelle sera conservée.`)) return; try { await removeCampaignPlayer(campaignId, member.user_id); await refresh(); setNotice("Joueur retiré. Sa page personnelle est conservée."); } catch (caught) { setError(caught instanceof Error ? caught.message : "Suppression impossible."); } }
  return <section className="panel campaign-access-panel">
    <div><p className="eyebrow">Accès de la campagne</p><h3>Joueurs et invitations</h3><p>Les liens invitent directement comme joueur ; une invitation révoquée ne peut plus être utilisée.</p></div>
    {error && <p className="form-error">{error}</p>}{notice && <p className="form-success">{notice}</p>}
    <div className="invite-create"><label>Expiration facultative<input type="date" min={new Date().toISOString().slice(0, 10)} value={expiresOn} onChange={(event) => setExpiresOn(event.target.value)} /></label><button type="button" className="button primary" onClick={() => void create()}><Plus size={17} />Créer une invitation</button></div>
    <div className="access-list"><h4>Invitations</h4>{invites.length === 0 && <p className="muted-copy">Aucune invitation créée.</p>}{invites.map((invite) => <article key={invite.id} className={invite.revoked_at ? "access-row muted" : "access-row"}><div><strong>{invite.revoked_at ? "Révoquée" : invite.expires_at && new Date(invite.expires_at) <= new Date() ? "Expirée" : "Active"}</strong><small>{link(invite)}</small></div><div><button type="button" className="button ghost" onClick={() => void copy(invite)}>Copier</button>{!invite.revoked_at && <button type="button" className="button ghost danger" onClick={() => void revoke(invite)}>Révoquer</button>}</div></article>)}</div>
    <div className="access-list"><h4>Membres</h4>{members.map((member) => <article key={member.user_id} className="access-row"><div><strong>{member.display_name}</strong><small>{member.role === "gm" ? "Maître de jeu" : "Joueur"}</small></div>{member.role === "player" && <button type="button" className="button ghost danger" onClick={() => void remove(member)}>Retirer</button>}</article>)}</div>
    <div className="access-list player-pages-list"><h4>Pages personnelles</h4><p className="muted-copy">Consultation uniquement : seul le joueur concerné peut modifier sa page.</p>{pages.length === 0 && <p className="muted-copy">Aucune page joueur pour le moment.</p>}{pages.map((page) => <article key={page.user_id} className={page.active ? "access-row" : "access-row muted"}><div><strong>{page.display_name}</strong><small>{page.character_name || "Personnage non renseigné"} · {page.active ? "Membre actuel" : "Hors campagne — page conservée"}</small></div><button type="button" className="button ghost" onClick={() => setOpenedPage(page)}><Eye size={16} />Consulter</button></article>)}</div>
    {openedPage && <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setOpenedPage(null); }}><article className="modal-card player-page-readonly" role="dialog" aria-modal="true" aria-labelledby="player-page-title"><header><div><p className="eyebrow">Page personnelle · lecture seule</p><h2 id="player-page-title">{openedPage.display_name}</h2></div><button type="button" className="icon-button" aria-label="Fermer" onClick={() => setOpenedPage(null)}><X size={18} /></button></header><dl><div><dt>Personnage</dt><dd>{openedPage.character_name || "Non renseigné"}</dd></div><div><dt>Présentation</dt><dd>{openedPage.character_summary || "Non renseignée"}</dd></div><div><dt>Objectifs</dt><dd>{openedPage.objectives || "Non renseignés"}</dd></div><div><dt>Notes personnelles</dt><dd>{openedPage.notes || "Aucune note"}</dd></div>{openedPage.pathbuilder_url && <div><dt>Pathbuilder</dt><dd><a href={openedPage.pathbuilder_url} target="_blank" rel="noreferrer">Ouvrir la fiche</a></dd></div>}</dl><footer><small>Dernière modification : {new Date(openedPage.updated_at).toLocaleString("fr-FR")}</small><button type="button" className="button secondary" onClick={() => setOpenedPage(null)}>Fermer</button></footer></article></div>}
  </section>;
}
