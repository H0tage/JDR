import { BookOpen, Check, ChevronDown, CircleHelp, CircleOff, Cloud, Eye, Focus, Gem, Handshake, Heart, ImagePlus, LayoutDashboard, List, LockKeyhole, Maximize2, Minimize2, Moon, Network, Pencil, Save, ScrollText, Sun, TriangleAlert, UserRound, Users, X } from "lucide-react";
import { useCallback, useEffect, useRef, useState, type CSSProperties, type FormEvent } from "react";
import { createPortal } from "react-dom";
import { contactPortraitUrl, loadPlayerData, savePlayerContactNotes, subscribeToCampaign } from "../lib/api";
import { highestAvailableService, unlockedServices } from "../lib/domain";
import { formatCopper, loadPlayerEconomy } from "../lib/playerEconomyApi";
import { deletePlayerCharacterImage, listCampaignPlayerPages, listMyPlayerRelationshipNotes, loadMyPlayerPage, playerCharacterImageUrl, saveMyPlayerPage, saveMyPlayerRelationshipNote, uploadPlayerCharacterImage, type CampaignPlayerPage, type PlayerPage, type PlayerPageDraft, type PlayerRelationshipNote } from "../lib/playerPageApi";
import type { CampaignData, CampaignInventoryItem, Contact, FactionOverview } from "../lib/types";
import { EmptyState, ErrorPanel, LoadingScreen, SectionHeading } from "./ui";
import { BestiaryTab } from "./BestiaryTab";
import { QuestJournalTab } from "./QuestJournalTab";
import { QuestWritingTab } from "./QuestWritingTab";
import { PlayerEconomyTab } from "./PlayerEconomyTab";
import { PathbuilderEmbed } from "./PathbuilderEmbed";

type PlayerTab = "dashboard" | "relations" | "bestiary" | "loot" | "my-page" | "player-pages" | "notes" | "quest-journal" | "help";
type PlayerTheme = "light" | "original" | "dark";

function storedPlayerTheme(): PlayerTheme {
  try {
    const current = window.localStorage.getItem("blood-lords-player-theme-v2");
    if (current === "light" || current === "original" || current === "dark") return current;
    // L'ancien thème sombre devient « Original » afin de ne pas changer
    // brutalement le rendu des personnes qui l'avaient déjà choisi.
    return window.localStorage.getItem("blood-lords-player-theme") === "dark" ? "original" : "light";
  } catch {
    return "light";
  }
}

function storedPlayerTab(): PlayerTab {
  try {
    const tab = window.localStorage.getItem("blood-lords-player-tab");
    if (tab === "politics") return "relations";
    return ["dashboard", "relations", "bestiary", "loot", "my-page", "player-pages", "notes", "quest-journal", "help"].includes(tab ?? "") ? tab as PlayerTab : "dashboard";
  } catch {
    return "dashboard";
  }
}

export function PlayerApp({ campaignId, campaignSlug, viewerRole = "player" }: { campaignId: string; campaignSlug?: string; viewerRole?: "gm" | "player" }) {
  const demo = new URLSearchParams(window.location.search).get("demo") === "1";
  const [data, setData] = useState<CampaignData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<PlayerTab>(storedPlayerTab);
  const [theme, setTheme] = useState<PlayerTheme>(storedPlayerTheme);
  const [notice, setNotice] = useState<string | null>(null);
  const tabsRef = useRef<HTMLElement | null>(null);
  const [tabsHeight, setTabsHeight] = useState(75);
  const [playerPages, setPlayerPages] = useState<CampaignPlayerPage[] | null>(null);
  const [playerPagesError, setPlayerPagesError] = useState<string | null>(null);
  const [selectedPlayerPage, setSelectedPlayerPage] = useState<CampaignPlayerPage | null>(null);

  const refresh = useCallback(async () => {
    try {
      setData(await loadPlayerData(campaignId, demo));
      setError(null);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Chargement impossible.");
    } finally {
      setLoading(false);
    }
  }, [campaignId, demo]);

  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => {
    void listCampaignPlayerPages(campaignId, demo)
      .then((pages) => { setPlayerPages(pages); setPlayerPagesError(null); })
      .catch((caught) => setPlayerPagesError(caught instanceof Error ? caught.message : "Chargement des pages joueurs impossible."));
  }, [campaignId, demo, viewerRole]);
  useEffect(() => {
    if (viewerRole === "gm" && tab === "my-page") setTab("help");
  }, [tab, viewerRole]);
  useEffect(() => {
    if (demo || !data) return;
    return subscribeToCampaign(data.settings.campaign_id, () => void refresh());
  }, [data?.settings.campaign_id, demo, refresh]);
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
  useEffect(() => {
    try {
      window.localStorage.setItem("blood-lords-player-theme-v2", theme);
    } catch {
      // L'affichage reste fonctionnel lorsqu'un navigateur bloque le stockage local.
    }
  }, [theme]);
  useEffect(() => {
    try {
      window.localStorage.setItem("blood-lords-player-tab", tab);
    } catch {
      // Le choix actif reste utilisable lorsqu'un navigateur bloque le stockage local.
    }
  }, [tab]);
  useEffect(() => {
    const tabs = tabsRef.current;
    if (!tabs) return;
    const measure = () => setTabsHeight(Math.ceil(tabs.getBoundingClientRect().height));
    measure();
    window.addEventListener("resize", measure);
    const observer = "ResizeObserver" in window ? new ResizeObserver(measure) : null;
    observer?.observe(tabs);
    return () => { window.removeEventListener("resize", measure); observer?.disconnect(); };
  }, [data]);

  function announce(message: string) {
    setNotice(message);
    window.setTimeout(() => setNotice(null), 3200);
  }

  if (loading) return <LoadingScreen label="Consultation des registres publics…" />;
  if (!data) return <main className="state-screen"><ErrorPanel error={error ?? "Vue indisponible."} onRetry={() => void refresh()} /><a className="button secondary" href="?demo=1">Ouvrir l’aperçu</a></main>;
  const intuitive = data.settings.player_display_mode === "intuitive";
  const themeClass = theme === "original" ? "dark" : theme === "dark" ? "github-dark" : "light";

  return (
    <div className={`player-shell player-theme-${themeClass}${theme === "dark" ? " player-theme-dark" : ""}`} style={{ "--player-tabs-height": `${tabsHeight}px` } as CSSProperties}>
      <header className="player-header">
        <a className="player-brand" href="/"><span><span>BL</span></span><div><strong>Registre du groupe</strong><small>{intuitive ? "Blood Lords · Campagne en cours" : `Blood Lords · Volume ${data.settings.current_volume}`}</small></div></a>
        <div className="player-header-actions">
          <fieldset className="player-theme-picker"><legend>Thème</legend>
            <label className={theme === "light" ? "active" : ""}><input type="radio" name="player-theme" checked={theme === "light"} onChange={() => setTheme("light")} /><Sun size={15} /><span>Clair</span></label>
            <label className={theme === "original" ? "active" : ""}><input type="radio" name="player-theme" checked={theme === "original"} onChange={() => setTheme("original")} /><Moon size={15} /><span>Original</span></label>
            <label className={theme === "dark" ? "active" : ""}><input type="radio" name="player-theme" checked={theme === "dark"} onChange={() => setTheme("dark")} /><Moon size={15} /><span>Sombre</span></label>
          </fieldset>
          {viewerRole === "gm" && campaignSlug && <a className="player-shortcut player-gm-shortcut" href={`/campaign/${campaignSlug}/mj`}><LockKeyhole size={18} /><span>Vue MJ</span></a>}
        </div>
      </header>
      <nav ref={tabsRef} className="player-tabs">
        <button className={tab === "dashboard" ? "active" : ""} onClick={() => setTab("dashboard")}><LayoutDashboard size={17} />Accueil</button>
        <button className={tab === "quest-journal" ? "active" : ""} onClick={() => setTab("quest-journal")}><BookOpen size={17} />Journal de quête</button>
        <button className={tab === "notes" ? "active" : ""} onClick={() => setTab("notes")}><ScrollText size={17} />Carnet de notes</button>
        <button className={tab === "relations" ? "active" : ""} onClick={() => setTab("relations")}><Eye size={17} />Relations</button>
        <button className={tab === "bestiary" ? "active" : ""} onClick={() => setTab("bestiary")}><BookOpen size={17} />Bestiaire</button>
        <button className={tab === "loot" ? "active" : ""} onClick={() => setTab("loot")}><Gem size={17} />Butins</button>
        <PlayerPagesMenu pages={playerPages} error={playerPagesError} theme={theme} viewerRole={viewerRole} active={tab === "my-page" || tab === "player-pages"} onOpenOwn={() => setTab("my-page")} onSelect={(page) => { if (page.is_own && viewerRole === "player") setTab("my-page"); else { setSelectedPlayerPage(page); setTab("player-pages"); } }} />
        <button className={tab === "help" ? "active" : ""} onClick={() => setTab("help")}><CircleHelp size={17} />Comment fonctionne ce site ?</button>
      </nav>
      <main className="player-content">
        {error && <ErrorPanel error={error} onRetry={() => void refresh()} />}
        {notice && <div className="player-toast">{notice}</div>}
        {tab === "dashboard" && <PlayerDashboard data={data} demo={demo} viewerRole={viewerRole} onOpen={setTab} />}
        {tab === "relations" && <PlayerRelations data={data} demo={demo} onChanged={refresh} onNotice={announce} onError={setError} />}
        {tab === "bestiary" && <BestiaryTab campaignId={data.settings.campaign_id} entries={data.bestiary} demo={demo} onChanged={refresh} onNotice={announce} onError={setError} />}
        {tab === "loot" && <PlayerEconomyTab campaignId={data.settings.campaign_id} demo={demo} viewerRole={viewerRole} />}
        {viewerRole === "player" && <div className="persistent-player-page" hidden={tab !== "my-page"}><PlayerPageTab campaignId={data.settings.campaign_id} demo={demo} active={tab === "my-page"} playerPages={playerPages ?? []} /></div>}
        {tab === "player-pages" && <PlayerPagesTab page={selectedPlayerPage} loading={playerPages === null && !playerPagesError} error={playerPagesError} viewerRole={viewerRole} />}
        {tab === "notes" && <QuestJournalTab campaignId={data.settings.campaign_id} entries={data.questEntries} factionHistory={[]} showFactionHistory={false} demo={demo} onChanged={refresh} onNotice={announce} onError={setError} />}
        {tab === "quest-journal" && <QuestWritingTab page={data.questJournalPage} revisions={data.questJournalRevisions} canRestoreHistory demo={demo} onChanged={refresh} onNotice={announce} onError={setError} />}
        {tab === "help" && <PlayerGuide />}
      </main>
      <footer className="player-footer"><span>Aide de jeu non officielle</span><p>{intuitive ? "Cette vue traduit la position du groupe auprès des factions sans en révéler les mécanismes chiffrés." : "Les RP représentent votre position publique et ne sont jamais dépensés. Les JF servent à solliciter un service."}</p></footer>
    </div>
  );
}

function PlayerPagesMenu({ pages, error, theme, viewerRole, active, onOpenOwn, onSelect }: {
  pages: CampaignPlayerPage[] | null;
  error: string | null;
  theme: PlayerTheme;
  viewerRole: "gm" | "player";
  active: boolean;
  onOpenOwn: () => void;
  onSelect: (page: CampaignPlayerPage) => void;
}) {
  const [open, setOpen] = useState(false);
  const [submenuPosition, setSubmenuPosition] = useState<{ top: number; left: number } | null>(null);
  const menuRef = useRef<HTMLDivElement | null>(null);
  const closeTimer = useRef<number | null>(null);
  function cancelClose() {
    if (closeTimer.current !== null) window.clearTimeout(closeTimer.current);
    closeTimer.current = null;
  }
  function scheduleClose() {
    cancelClose();
    closeTimer.current = window.setTimeout(() => setOpen(false), 300);
  }
  useEffect(() => {
    if (!open) { setSubmenuPosition(null); return; }
    const rect = menuRef.current?.getBoundingClientRect();
    if (!rect) return;
    setSubmenuPosition({ top: rect.bottom + 5, left: Math.max(8, Math.min(rect.left, window.innerWidth - 265)) });
  }, [open]);
  useEffect(() => () => cancelClose(), []);
  const submenuThemeClass = theme === "original" ? " player-pages-submenu-dark" : theme === "dark" ? " player-pages-submenu-github-dark" : "";
  const submenu = open && createPortal(<div className={`player-pages-submenu${submenuThemeClass}`} role="menu" style={submenuPosition ?? undefined} onMouseEnter={cancelClose} onMouseLeave={scheduleClose} onFocus={cancelClose} onBlur={scheduleClose}>
      {error && <span className="player-pages-submenu-message">Pages indisponibles</span>}
      {!error && pages === null && <span className="player-pages-submenu-message">Chargement…</span>}
      {!error && viewerRole === "player" && <button type="button" role="menuitem" className="player-pages-own-link" onClick={() => { onOpenOwn(); setOpen(false); }}><span>Ma page</span><small>Ma fiche et Pathbuilder</small></button>}
      {!error && pages?.filter((page) => viewerRole === "gm" || !page.is_own).length === 0 && viewerRole === "gm" && <span className="player-pages-submenu-message">Pas encore de joueurs</span>}
      {!error && pages?.filter((page) => viewerRole === "gm" || !page.is_own).map((page) => <button type="button" role="menuitem" key={page.user_id} onClick={() => { onSelect(page); setOpen(false); }}><span>{page.display_name}</span><small>{page.active ? (page.character_name || "Personnage non renseigné") : "Hors campagne"}</small></button>)}
    </div>, document.body);
  return <div ref={menuRef} className="player-pages-menu" onMouseEnter={() => { cancelClose(); setOpen(true); }} onMouseLeave={scheduleClose} onFocus={() => { cancelClose(); setOpen(true); }} onBlur={(event) => { if (!event.currentTarget.contains(event.relatedTarget as Node | null)) scheduleClose(); }}>
    <button type="button" className={active || open ? "active" : ""} aria-haspopup="menu" aria-expanded={open} onClick={() => { if (viewerRole === "player") { onOpenOwn(); setOpen(false); } else { cancelClose(); setOpen(true); } }}><Users size={17} />Pages des joueurs</button>
    <button type="button" className={`player-pages-menu-toggle${active || open ? " active" : ""}`} aria-label="Choisir une page joueur" aria-haspopup="menu" aria-expanded={open} onClick={() => { cancelClose(); setOpen((current) => !current); }}><ChevronDown size={14} /></button>
    {submenu}
  </div>;
}

function PlayerDashboard({ data, demo, viewerRole, onOpen }: { data: CampaignData; demo: boolean; viewerRole: "gm" | "player"; onOpen: (tab: PlayerTab) => void }) {
  const [loot, setLoot] = useState<CampaignInventoryItem[] | null>(null);
  const activeNotes = data.questEntries.filter((entry) => entry.status === "Actif");
  const visibleContacts = data.contacts.filter((contact) => contact.visibility === "players");
  const datedBestiary = [...data.bestiary]
    .filter((entry) => entry.updated_at || entry.created_at)
    .sort((left, right) => new Date(right.updated_at ?? right.created_at ?? 0).getTime() - new Date(left.updated_at ?? left.created_at ?? 0).getTime())
    .slice(0, 3);

  useEffect(() => {
    void loadPlayerEconomy(data.settings.campaign_id, demo).then((economy) => setLoot(economy.items.filter((item) => item.status === "active"))).catch(() => setLoot([]));
  }, [data.settings.campaign_id, demo]);

  const recentLoot = [...(loot ?? [])].sort((left, right) => right.acquired_on.localeCompare(left.acquired_on)).slice(0, 3);
  return <div className="page-stack player-dashboard">
    <section className="player-dashboard-hero">
      <div><p className="eyebrow">Tableau de campagne</p><h1>Bienvenue dans les registres</h1><p>Retrouvez ici les informations utiles avant de replonger dans l’aventure.</p></div>
      <button className="button" onClick={() => onOpen("quest-journal")}><BookOpen size={17} />Reprendre le journal</button>
    </section>
    <section className="player-dashboard-metrics" aria-label="Résumé de la campagne">
      <button onClick={() => onOpen("notes")}><ScrollText /><span><strong>{activeNotes.length}</strong><small>élément{activeNotes.length === 1 ? "" : "s"} actif{activeNotes.length === 1 ? "" : "s"}</small></span></button>
      <button onClick={() => onOpen("loot")}><Gem /><span><strong>{loot === null ? "…" : loot.length}</strong><small>butin{loot?.length === 1 ? "" : "s"} partagé{loot?.length === 1 ? "" : "s"}</small></span></button>
      <button onClick={() => onOpen("relations")}><Users /><span><strong>{visibleContacts.length}</strong><small>contact{visibleContacts.length === 1 ? "" : "s"} connu{visibleContacts.length === 1 ? "" : "s"}</small></span></button>
      <button onClick={() => onOpen("bestiary")}><BookOpen /><span><strong>{data.bestiary.length}</strong><small>créature{data.bestiary.length === 1 ? "" : "s"} recensée{data.bestiary.length === 1 ? "" : "s"}</small></span></button>
    </section>
    <div className="player-dashboard-columns">
      <section className="player-dashboard-panel"><header><div><p className="eyebrow">À reprendre</p><h2>Notes actives</h2></div><button onClick={() => onOpen("notes")}>Tout voir</button></header>{activeNotes.length ? <ul>{activeNotes.slice(0, 4).map((entry) => <li key={entry.id}><button onClick={() => onOpen("notes")}><span>{entry.category}</span><strong>{entry.title}</strong>{entry.notes && <small>{entry.notes}</small>}</button></li>)}</ul> : <p className="player-dashboard-empty">Aucune piste active pour le moment.</p>}</section>
      <section className="player-dashboard-panel"><header><div><p className="eyebrow">Dernières publications</p><h2>Butins partagés</h2></div><button onClick={() => onOpen("loot")}>Tout voir</button></header>{loot === null ? <p className="player-dashboard-empty">Consultation du registre…</p> : recentLoot.length ? <ul>{recentLoot.map((item) => <li key={item.id}><button onClick={() => onOpen("loot")}><span>{new Date(`${item.acquired_on}T12:00:00`).toLocaleDateString("fr-FR")}</span><strong>{item.name}</strong><small>{item.owner_display_name ? `Attribué à ${item.owner_display_name}` : "Compte commun"}</small></button></li>)}</ul> : <p className="player-dashboard-empty">Aucun butin partagé pour le moment.</p>}</section>
    </div>
    <section className="player-dashboard-panel player-dashboard-bestiary"><header><div><p className="eyebrow">Registre vivant</p><h2>Créatures récemment consignées</h2></div><button onClick={() => onOpen("bestiary")}>Ouvrir le bestiaire</button></header>{datedBestiary.length ? <div>{datedBestiary.map((entry) => <button key={entry.id} onClick={() => onOpen("bestiary")}><BookOpen size={18} /><span><strong>{entry.name}</strong><small>{entry.updated_at || entry.created_at ? new Date(entry.updated_at ?? entry.created_at ?? "").toLocaleDateString("fr-FR") : ""}</small></span></button>)}</div> : <p className="player-dashboard-empty">Les créatures recensées apparaîtront ici dès qu’une date d’ajout sera disponible.</p>}</section>
    <nav className="player-dashboard-shortcuts" aria-label="Accès rapides"><button onClick={() => onOpen("relations")}><Eye size={17} />Relations</button><button onClick={() => onOpen("loot")}><Gem size={17} />Butins</button><button onClick={() => onOpen(viewerRole === "player" ? "my-page" : "player-pages")}><Users size={17} />Pages des joueurs</button></nav>
  </div>;
}

function PlayerPagesTab({ page, loading, error, viewerRole }: { page: CampaignPlayerPage | null; loading: boolean; error: string | null; viewerRole: "gm" | "player" }) {
  const [portraitOpen, setPortraitOpen] = useState(false);
  if (loading) return <LoadingScreen label="Chargement des pages joueurs…" />;
  if (error) return <ErrorPanel error={error} />;
  if (!page) return <div className="page-stack"><SectionHeading eyebrow="Fiches de la campagne" title="Pages des joueurs" /><EmptyState title="Sélectionnez une page joueur">Choisissez un joueur dans le menu « Pages des joueurs » pour consulter sa fiche.</EmptyState></div>;
  const portrait = playerCharacterImageUrl(page.image_path);
  return <div className="page-stack player-page-tab player-pages-readonly">
    <SectionHeading eyebrow={`${page.display_name}${page.active ? "" : " · hors campagne"}`} title={`Page de ${page.display_name}`} />
    <p className="player-page-privacy"><LockKeyhole size={17} /><span><strong>Lecture seule.</strong> Tous les membres de la campagne peuvent consulter cette fiche, mais seul son propriétaire peut la modifier.{viewerRole === "gm" ? " En tant que MJ, vous voyez aussi ses notes privées." : " Ses notes privées et Pathbuilder restent masqués."}</span></p>
    <div className="player-character-sheet">
      <section className="player-character-hero player-character-hero-readonly">{portrait ? <button type="button" className="player-character-portrait player-character-portrait-button" onClick={() => setPortraitOpen(true)} title="Agrandir l’illustration"><img src={portrait} alt={page.character_name ? `Illustration de ${page.character_name}` : `Illustration de ${page.display_name}`} /><span><Maximize2 size={16} />Agrandir</span></button> : <div className="player-character-portrait"><div><UserRound size={48} /><span>Aucune illustration</span></div></div>}<div className="player-character-intro"><p className="eyebrow">Personnage de {page.display_name}</p><h1>{page.character_name || "Personnage sans nom"}</h1><p>{page.character_summary || "Aucune présentation renseignée."}</p></div></section>
      <div className="player-character-details"><section><p className="eyebrow">Intentions</p><h2>Objectifs</h2><p>{page.objectives || "Aucun objectif renseigné."}</p></section>{viewerRole === "gm" && <section><p className="eyebrow">Confidentiel</p><h2>Notes privées</h2><p>{page.notes || "Aucune note privée."}</p></section>}</div>
      <p className="player-character-updated">Dernière modification : {new Date(page.updated_at).toLocaleString("fr-FR")}</p>
    </div>
    {portraitOpen && portrait && <CharacterImageLightbox src={portrait} name={page.character_name || page.display_name} onClose={() => setPortraitOpen(false)} />}
  </div>;
}

function PlayerGuide() {
  return <div className="page-stack player-site-guide">
    <SectionHeading eyebrow="Guide de la table" title="Comment fonctionne ce site ?" />
    <section className="player-guide-intro"><strong>Bienvenue sur le Registre du groupe.</strong><p>Ce registre, dédié aux joueurs de la campagne Blood Lords, permet aux joueurs de suivre l’évolution de leur aventure, de prendre des notes, de lister les créatures rencontrées, etc. Ci-dessous, une présentation succincte du site.</p></section>
    <section className="player-guide-grid">
      <article><ScrollText size={20} /><div><h3>Journal de quête</h3><p>Rédigez les notes de séance au fil de la partie. Les séances peuvent être repliées, datées, mises en forme et verrouillées pour éviter une modification accidentelle.</p></div></article>
      <article><BookOpen size={20} /><div><h3>Carnet de notes</h3><p>Consignez rapidement une piste, une question, une rumeur ou toute information à garder en tête.</p></div></article>
      <article><Eye size={20} /><div><h3>Relations</h3><p>Consultez ce que les factions connaissent du groupe, leur disposition, les contacts révélés et les services éventuellement accessibles.</p></div></article>
      <article><BookOpen size={20} /><div><h3>Bestiaire</h3><p>Ajoutez ou consultez les créatures rencontrées, leurs résistances, faiblesses et notes utiles au groupe.</p></div></article>
      <article><Gem size={20} /><div><h3>Butins</h3><p>Consultez les objets que le MJ a ajoutés à l’inventaire partagé du groupe.</p></div></article>
      <article><UserRound size={20} /><div><h3>Pages des joueurs</h3><p>Consultez les fiches des personnages de la campagne. Votre page est la seule que vous pouvez modifier et la seule à donner accès à votre Pathbuilder et à vos notes privées.</p></div></article>
      <article><Network size={20} /><div><h3>Politique connue</h3><p>La carte des rapports entre factions apparaît en bas de la page Relations lorsque le groupe en connaît suffisamment.</p></div></article>
      <article><Sun size={20} /><div><h3>Préférences d’affichage</h3><p>Les thèmes Clair, Original et Sombre sont propres à votre navigateur. Le dernier onglet ouvert est également conservé sur cet appareil.</p></div></article>
    </section>
  </div>;
}

function emptyPlayerPageDraft(page: PlayerPage): PlayerPageDraft {
  return {
    character_name: page.character_name ?? "",
    character_summary: page.character_summary ?? "",
    pathbuilder_url: page.pathbuilder_url ?? "",
    notes: page.notes ?? "",
    objectives: page.objectives ?? "",
    image_path: page.image_path ?? null,
  };
}

const PATHBUILDER_FOCUS_STORAGE_KEY = "blood-lords-pathbuilder-focused";

function storedPathbuilderFocus(): boolean {
  try {
    return window.localStorage.getItem(PATHBUILDER_FOCUS_STORAGE_KEY) === "1";
  } catch {
    return false;
  }
}

function PlayerPageTab({ campaignId, demo, active, playerPages }: { campaignId: string; demo: boolean; active: boolean; playerPages: CampaignPlayerPage[] }) {
  const [pageView, setPageView] = useState<"register" | "pathbuilder">("register");
  const [pathbuilderOpened, setPathbuilderOpened] = useState(false);
  const [pathbuilderFocusPreference, setPathbuilderFocusPreference] = useState(storedPathbuilderFocus);
  const [pathbuilderFocused, setPathbuilderFocused] = useState(false);
  const pageViewTabsRef = useRef<HTMLDivElement | null>(null);
  const scrollLockRef = useRef<{ bodyOverflowY: string; htmlOverscrollY: string } | null>(null);
  const [page, setPage] = useState<PlayerPage | null>(null);
  const [draft, setDraft] = useState<PlayerPageDraft | null>(null);
  const [possessions, setPossessions] = useState<CampaignInventoryItem[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [editing, setEditing] = useState(false);
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [portraitOpen, setPortraitOpen] = useState(false);
  const [relationshipNotes, setRelationshipNotes] = useState<PlayerRelationshipNote[]>([]);

  const releasePathbuilderFocus = useCallback((updateState = true) => {
    const previous = scrollLockRef.current;
    if (previous) {
      document.body.style.overflowY = previous.bodyOverflowY;
      document.documentElement.style.overscrollBehaviorY = previous.htmlOverscrollY;
      scrollLockRef.current = null;
    }
    if (updateState) setPathbuilderFocused(false);
  }, []);

  const activatePathbuilderFocus = useCallback(() => {
    if (scrollLockRef.current) return;
    pageViewTabsRef.current?.scrollIntoView?.({ block: "start" });
    scrollLockRef.current = {
      bodyOverflowY: document.body.style.overflowY,
      htmlOverscrollY: document.documentElement.style.overscrollBehaviorY,
    };
    document.body.style.overflowY = "hidden";
    document.documentElement.style.overscrollBehaviorY = "none";
    setPathbuilderFocused(true);
  }, []);

  useEffect(() => () => releasePathbuilderFocus(false), [releasePathbuilderFocus]);
  useEffect(() => {
    if (!active || pageView !== "pathbuilder") {
      if (pathbuilderFocused) releasePathbuilderFocus();
      return;
    }
    if (pathbuilderFocusPreference && !pathbuilderFocused) activatePathbuilderFocus();
    if (!pathbuilderFocusPreference && pathbuilderFocused) releasePathbuilderFocus();
  }, [activatePathbuilderFocus, active, pageView, pathbuilderFocusPreference, pathbuilderFocused, releasePathbuilderFocus]);
  useEffect(() => {
    try {
      window.localStorage.setItem(PATHBUILDER_FOCUS_STORAGE_KEY, pathbuilderFocusPreference ? "1" : "0");
    } catch {
      // Le mode reste utilisable même si le navigateur bloque le stockage local.
    }
  }, [pathbuilderFocusPreference]);

  function togglePathbuilderFocus() {
    const nextPreference = !pathbuilderFocusPreference;
    setPathbuilderFocusPreference(nextPreference);
    if (!nextPreference) {
      releasePathbuilderFocus();
    }
  }

  const refresh = useCallback(async () => {
    try {
      const [nextPage, economy, nextRelationshipNotes] = await Promise.all([loadMyPlayerPage(campaignId, demo), loadPlayerEconomy(campaignId, demo), listMyPlayerRelationshipNotes(campaignId, demo)]);
      setPage(nextPage);
      setDraft(emptyPlayerPageDraft(nextPage));
      setPossessions(economy.items.filter((item) => item.status === "active" && item.owner_user_id === nextPage.user_id));
      setRelationshipNotes(nextRelationshipNotes);
      setError(null);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Chargement de votre page impossible.");
    }
  }, [campaignId, demo]);

  useEffect(() => { void refresh(); }, [refresh]);

  async function save(event: FormEvent) {
    event.preventDefault();
    if (!draft || !page) return;
    setSaving(true); setSaved(false); setError(null);
    let uploadedPath: string | null = null;
    try {
      uploadedPath = imageFile ? await uploadPlayerCharacterImage(campaignId, page.user_id, imageFile, demo) : null;
      const nextDraft = { ...draft, image_path: uploadedPath ?? draft.image_path };
      await saveMyPlayerPage(campaignId, nextDraft, demo);
      if (page.image_path && page.image_path !== nextDraft.image_path) await deletePlayerCharacterImage(page.image_path, demo);
      setPage({ ...page, ...nextDraft, updated_at: new Date().toISOString() });
      setDraft(nextDraft);
      setImageFile(null); setImagePreview(null); setEditing(false);
      setSaved(true);
    } catch (caught) {
      if (uploadedPath) await deletePlayerCharacterImage(uploadedPath, demo).catch(() => undefined);
      setError(caught instanceof Error ? caught.message : "Enregistrement impossible.");
    } finally { setSaving(false); }
  }

  if (!page || !draft) {
    if (error) return <ErrorPanel error={error} onRetry={() => void refresh()} />;
    return <LoadingScreen label="Ouverture de votre page…" />;
  }

  function cancelEdit() {
    if (!page) return;
    if (imagePreview?.startsWith("blob:")) URL.revokeObjectURL(imagePreview);
    setDraft(emptyPlayerPageDraft(page)); setImageFile(null); setImagePreview(null); setEditing(false); setError(null);
  }

  function chooseImage(file: File | null) {
    if (imagePreview?.startsWith("blob:")) URL.revokeObjectURL(imagePreview);
    setImageFile(file);
    setImagePreview(file ? URL.createObjectURL(file) : null);
  }

  const portrait = imagePreview ?? playerCharacterImageUrl(draft.image_path);

  return <div className={`page-stack player-page-tab${pathbuilderFocused ? " pathbuilder-focus-mode" : ""}`}>
    <div className="player-page-heading"><SectionHeading eyebrow={page.display_name ?? "Votre espace"} title="Ma page" />{pageView === "register" && !editing && <button className="button secondary" onClick={() => { setEditing(true); setSaved(false); }}><Pencil size={16} />Modifier ma page</button>}</div>
    <div ref={pageViewTabsRef} className="player-page-view-controls"><nav className="player-page-view-tabs" aria-label="Contenu de ma page">
      <button type="button" className={pageView === "register" ? "active" : ""} aria-current={pageView === "register" ? "page" : undefined} onClick={() => setPageView("register")}><UserRound size={17} />Page Registre</button>
      <button type="button" className={pageView === "pathbuilder" ? "active" : ""} aria-current={pageView === "pathbuilder" ? "page" : undefined} onClick={() => { setPathbuilderOpened(true); setPageView("pathbuilder"); }}><BookOpen size={17} />Page Pathbuilder2e</button>
    </nav>{pageView === "pathbuilder" && <button type="button" className={`player-page-focus-button${pathbuilderFocused ? " active" : ""}`} aria-pressed={pathbuilderFocused} onClick={togglePathbuilderFocus}>{pathbuilderFocused ? <Minimize2 size={17} /> : <Focus size={17} />}<span>{pathbuilderFocused ? "Libérer la page" : "Cadrer Pathbuilder"}</span></button>}</div>
    {error && <p className="form-error" role="alert">{error}</p>}
    {saved && <p className="form-success" role="status">Votre page est enregistrée.</p>}
    <div className="player-page-register-view" hidden={pageView !== "register"}><p className="player-page-privacy"><LockKeyhole size={17} /><span><strong>Votre fiche de campagne.</strong> Les autres joueurs peuvent la consulter en lecture seule. Vos notes privées restent visibles uniquement par vous et le MJ.</span></p>{editing ? <form className="player-page-edit" onSubmit={save}>
      <section className="player-page-edit-portrait"><div>{portrait ? <img src={portrait} alt="Aperçu du personnage" /> : <ImagePlus size={40} />}</div><label className="button secondary"><ImagePlus size={16} />Choisir une illustration<input type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => chooseImage(event.target.files?.[0] ?? null)} /></label>{(draft.image_path || imageFile) && <button type="button" className="text-button danger-text" onClick={() => { chooseImage(null); setDraft({ ...draft, image_path: null }); }}>Retirer l’image</button>}<small>JPEG, PNG ou WebP · 8 Mo maximum.</small></section>
      <section className="player-page-edit-fields"><label>Nom du personnage<input maxLength={120} value={draft.character_name ?? ""} onChange={(event) => setDraft({ ...draft, character_name: event.target.value })} placeholder="Nom utilisé en jeu" /></label><label>Présentation<textarea maxLength={4000} value={draft.character_summary ?? ""} onChange={(event) => setDraft({ ...draft, character_summary: event.target.value })} placeholder="Concept, parcours et éléments importants…" /></label><label>Lien Pathbuilder<input type="url" maxLength={500} value={draft.pathbuilder_url ?? ""} onChange={(event) => setDraft({ ...draft, pathbuilder_url: event.target.value })} placeholder="https://pathbuilder2e.com/…" /></label></section>
      <section className="player-page-edit-wide"><label>Objectifs partagés<textarea maxLength={10000} value={draft.objectives ?? ""} onChange={(event) => setDraft({ ...draft, objectives: event.target.value })} placeholder="Objectifs, pistes à suivre, promesses…" /></label><label>Notes privées <small>visibles uniquement par vous et le MJ</small><textarea className="player-page-notes" maxLength={20000} value={draft.notes ?? ""} onChange={(event) => setDraft({ ...draft, notes: event.target.value })} placeholder="Repères personnels, secrets, réflexions…" /></label></section>
      <div className="player-page-submit"><small>Cette page reste conservée si vous quittez temporairement la campagne.</small><div><button type="button" className="button secondary" onClick={cancelEdit}>Annuler</button><button className="button primary" disabled={saving}><Save size={17} />{saving ? "Enregistrement…" : "Enregistrer"}</button></div></div>
    </form> : <div className="player-character-sheet">
      <section className="player-character-hero">{portrait ? <button type="button" className="player-character-portrait player-character-portrait-button" onClick={() => setPortraitOpen(true)} title="Agrandir l’illustration"><img src={portrait} alt={page.character_name ? `Illustration de ${page.character_name}` : "Illustration du personnage"} /><span><Maximize2 size={16} />Agrandir</span></button> : <div className="player-character-portrait"><div><UserRound size={48} /><span>Ajoutez une illustration</span></div></div>}<div className="player-character-intro"><p className="eyebrow">Personnage de {page.display_name}</p><h1>{page.character_name || "Personnage sans nom"}</h1><p>{page.character_summary || "Ajoutez une présentation pour donner vie à votre personnage dans les registres."}</p>{page.pathbuilder_url && <a className="button secondary" href={page.pathbuilder_url} target="_blank" rel="noreferrer"><BookOpen size={16} />Ouvrir la fiche Pathbuilder</a>}</div></section>
      <div className="player-character-details"><section><p className="eyebrow">Intentions</p><h2>Objectifs</h2><p>{page.objectives || "Aucun objectif renseigné pour le moment."}</p></section><section><p className="eyebrow">Confidentiel</p><h2>Notes privées</h2><p>{page.notes || "Aucune note privée."}</p></section></div>
      <section className="player-character-possessions player-page-possessions"><div><p className="eyebrow">Inventaire personnel</p><h2>Mes possessions</h2></div>{possessions.length ? <ul>{possessions.map((item) => <li key={item.id}><strong>{item.name}</strong><span>{item.quantity}{item.unit_value_cp !== null ? ` · ${formatCopper(item.unit_value_cp)}` : ""}</span></li>)}</ul> : <p>Aucun butin ne vous est attribué pour le moment.</p>}</section>
      <PlayerRelationshipCards campaignId={campaignId} demo={demo} pages={playerPages.filter((candidate) => candidate.active && candidate.user_id !== page.user_id)} notes={relationshipNotes} onSaved={(targetUserId, notes) => setRelationshipNotes((current) => [...current.filter((entry) => entry.target_user_id !== targetUserId), { target_user_id: targetUserId, notes: notes || null, updated_at: new Date().toISOString() }])} />
      <p className="player-character-updated">Dernière modification : {new Date(page.updated_at).toLocaleString("fr-FR")}</p>
    </div>}</div>
    {pathbuilderOpened && <div className="player-page-pathbuilder-view" hidden={pageView !== "pathbuilder"}><PathbuilderEmbed /><PlayerPossessionsSummary possessions={possessions} /></div>}
    {portraitOpen && portrait && <CharacterImageLightbox src={portrait} name={page.character_name || "votre personnage"} onClose={() => setPortraitOpen(false)} />}
  </div>;
}

function PlayerPossessionsSummary({ possessions }: { possessions: CampaignInventoryItem[] }) {
  return <section className="pathbuilder-possessions player-character-possessions player-page-possessions">
    <div><p className="eyebrow">Rappel du registre</p><h2>Mes possessions</h2><small>Inventaire issu du gestionnaire de butins</small></div>
    {possessions.length ? <ul>{possessions.map((item) => <li key={item.id}><strong>{item.name}</strong><span>{item.quantity}{item.unit_value_cp !== null ? ` · ${formatCopper(item.unit_value_cp)}` : ""}</span></li>)}</ul> : <p>Aucun butin ne vous est attribué pour le moment.</p>}
  </section>;
}

function PlayerRelationshipCards({ campaignId, demo, pages, notes, onSaved }: { campaignId: string; demo: boolean; pages: CampaignPlayerPage[]; notes: PlayerRelationshipNote[]; onSaved: (targetUserId: string, notes: string) => void }) {
  if (!pages.length) return null;
  return <section className="player-party-relations">
    <header><div><p className="eyebrow">Compagnons de route</p><h2>Les autres personnages</h2></div><small>Vos notes sur eux sont privées et ne sont jamais partagées.</small></header>
    <div>{pages.map((page) => <PlayerRelationshipCard key={page.user_id} campaignId={campaignId} demo={demo} page={page} initialNotes={notes.find((entry) => entry.target_user_id === page.user_id)?.notes ?? ""} onSaved={onSaved} />)}</div>
  </section>;
}

function PlayerRelationshipCard({ campaignId, demo, page, initialNotes, onSaved }: { campaignId: string; demo: boolean; page: CampaignPlayerPage; initialNotes: string; onSaved: (targetUserId: string, notes: string) => void }) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(initialNotes);
  const [saved, setSaved] = useState(initialNotes);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { setDraft(initialNotes); setSaved(initialNotes); }, [initialNotes]);
  async function submit(event: FormEvent) {
    event.preventDefault();
    setSaving(true); setError(null);
    try {
      const next = draft.trim();
      await saveMyPlayerRelationshipNote(campaignId, page.user_id, next, demo);
      setSaved(next); setDraft(next); setEditing(false); onSaved(page.user_id, next);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Enregistrement impossible.");
    } finally { setSaving(false); }
  }
  const portrait = playerCharacterImageUrl(page.image_path);
  return <article className="player-party-relation-card">
    <header><span className="contact-portrait">{portrait ? <img src={portrait} alt="" /> : <UserRound size={19} aria-hidden="true" />}</span><div><small>{page.display_name}</small><h3>{page.character_name || "Personnage non renseigné"}</h3></div></header>
    {!editing ? <><p>{saved || "Aucune note privée sur ce personnage."}</p><button type="button" className="contact-notes-toggle" onClick={() => setEditing(true)}><Pencil size={14} />{saved ? "Modifier mes notes" : "Ajouter une note"}</button></> : <form onSubmit={(event) => void submit(event)}><label>Notes privées<textarea maxLength={10000} value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="Souvenirs, promesses, dynamique entre vos personnages…" /></label>{error && <small className="form-error">{error}</small>}<div><button type="button" className="button tiny secondary" disabled={saving} onClick={() => { setDraft(saved); setEditing(false); setError(null); }}>Annuler</button><button className="button tiny primary" disabled={saving}><Save size={14} />{saving ? "Enregistrement…" : "Enregistrer"}</button></div></form>}
  </article>;
}

function CharacterImageLightbox({ src, name, onClose }: { src: string; name: string; onClose: () => void }) {
  return <div className="modal-backdrop bestiary-lightbox" role="presentation" onClick={onClose}><section className="bestiary-lightbox-card character-lightbox-card" role="dialog" aria-modal="true" aria-label={`Illustration de ${name}`} onClick={(event) => event.stopPropagation()}><header><strong>{name}</strong><button type="button" className="icon-button" onClick={onClose} aria-label="Fermer l’image"><X /></button></header><img src={src} alt={`Illustration de ${name}`} /></section></div>;
}

export function PlayerRelations({ data, demo, onChanged, onNotice, onError }: {
  data: CampaignData;
  demo: boolean;
  onChanged: () => Promise<void>;
  onNotice: (message: string) => void;
  onError: (message: string | null) => void;
}) {
  const visibleFactions = data.factions.filter((faction) => faction.is_player_visible);
  const intuitive = data.settings.player_display_mode === "intuitive";
  const [openedContact, setOpenedContact] = useState<Contact | null>(null);
  const [view, setView] = useState<"cards" | "list">("cards");
  const visibleContacts = [...data.contacts].filter((contact) => contact.visibility === "players").sort((left, right) => left.name.localeCompare(right.name, "fr", { sensitivity: "base" }));
  return (
    <div className="page-stack">
      <div className="relations-heading"><SectionHeading eyebrow={intuitive ? "Alliances et appréciation" : "Réputation et faveurs"} title="Vos relations" /><nav aria-label="Mode d’affichage des relations"><button type="button" className={view === "cards" ? "active" : ""} onClick={() => setView("cards")}><Users size={15} />Cartes</button><button type="button" className={view === "list" ? "active" : ""} onClick={() => setView("list")}><List size={15} />Liste</button></nav></div>
      {view === "cards" ? (visibleFactions.length > 0 ? <section className="player-faction-grid">{visibleFactions.map((faction) => <PlayerFactionCard key={faction.faction_id} faction={faction} data={data} contacts={data.contacts.filter((contact) => contact.faction_id === faction.faction_id)} onOpenContact={setOpenedContact} />)}</section> : <EmptyState title="Aucune faction révélée">Le MJ fera apparaître les factions rencontrées ici.</EmptyState>) : visibleContacts.length ? <section className="player-contact-list" aria-label="Contacts connus par ordre alphabétique">{visibleContacts.map((contact) => <button type="button" key={contact.id} onClick={() => setOpenedContact(contact)}><ContactPortrait contact={contact} /><span><strong>{contact.name}</strong><small>{contact.role || "Contact connu"}</small></span><em>{contact.faction_name}</em></button>)}</section> : <EmptyState title="Aucun contact révélé">Les contacts connus apparaîtront ici.</EmptyState>}
      {data.relationships.length > 0 && <details className="player-politics-details"><summary><span><Network size={17} />Carte politique connue</span><small>Vue d’ensemble</small></summary><PlayerPolitics data={data} compact /></details>}
      {openedContact && <PlayerContactDialog contact={openedContact} demo={demo} onChanged={onChanged} onNotice={onNotice} onError={onError} onClose={() => setOpenedContact(null)} />}
    </div>
  );
}

type ContactNotesDraft = {
  character: string;
  debts: string;
  notes: string;
};

function contactNotesDraft(contact: Contact): ContactNotesDraft {
  return {
    character: contact.player_character_notes ?? "",
    debts: contact.player_debt_notes ?? "",
    notes: contact.player_notes ?? "",
  };
}

export function PlayerContactCard({ contact, demo, onChanged, onNotice, onError, showIdentity = true }: {
  contact: Contact;
  demo: boolean;
  onChanged: () => Promise<void>;
  onNotice: (message: string) => void;
  onError: (message: string | null) => void;
  showIdentity?: boolean;
}) {
  const [editing, setEditing] = useState(false);
  const [savedNotes, setSavedNotes] = useState(() => contactNotesDraft(contact));
  const [draft, setDraft] = useState(() => contactNotesDraft(contact));
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const next = contactNotesDraft(contact);
    setSavedNotes(next);
    if (!editing) setDraft(next);
  }, [contact.id, contact.player_character_notes, contact.player_debt_notes, contact.player_notes]);

  function cancel() {
    setDraft(savedNotes);
    setEditing(false);
  }

  async function save(event: FormEvent) {
    event.preventDefault();
    const next = {
      character: draft.character.trim(),
      debts: draft.debts.trim(),
      notes: draft.notes.trim(),
    };
    setSaving(true);
    onError(null);
    try {
      if (!demo) await savePlayerContactNotes({ contactId: contact.id, characterNotes: next.character, debtNotes: next.debts, notes: next.notes });
      setSavedNotes(next);
      setDraft(next);
      setEditing(false);
      if (!demo) await onChanged();
      onNotice("Notes du contact enregistrées.");
    } catch (caught) {
      onError(caught instanceof Error ? caught.message : "Enregistrement des notes impossible.");
    } finally {
      setSaving(false);
    }
  }

  const hasNotes = Boolean(savedNotes.character || savedNotes.debts || savedNotes.notes);
  return <article className={`known-contact-card${editing ? " is-editing" : ""}`}>
    {showIdentity && <div className="contact-icon"><Users size={19} /></div>}
    <div className="known-contact-body">{showIdentity && <><small>{contact.faction_name}</small><h3>{contact.name}</h3><p>{contact.role}</p>{contact.promise_debt && <blockquote>{contact.promise_debt}</blockquote>}</>}
      {!editing && <>
        {hasNotes && <section className="contact-player-notes">
          {savedNotes.character && <div><strong>Caractère et repères</strong><p>{savedNotes.character}</p></div>}
          {savedNotes.debts && <div><strong>Promesses et dettes</strong><p>{savedNotes.debts}</p></div>}
          {savedNotes.notes && <div><strong>Notes libres</strong><p>{savedNotes.notes}</p></div>}
        </section>}
        <button type="button" className="contact-notes-toggle" onClick={() => setEditing(true)}><Pencil size={14} />Éditer le contact</button>
      </>}
      {editing && <form className="contact-notes-editor" onSubmit={save}>
        <p className="contact-notes-intro">Ces notes sont partagées avec le groupe et visibles par le MJ.</p>
        <label>Caractère et repères<textarea value={draft.character} onChange={(event) => setDraft({ ...draft, character: event.target.value })} placeholder="Tempérament, habitudes, ce qui semble lui plaire…" /></label>
        <label>Promesses et dettes<textarea value={draft.debts} onChange={(event) => setDraft({ ...draft, debts: event.target.value })} placeholder="Ce que le groupe lui doit, ou ce qu’il doit au groupe…" /></label>
        <label>Notes libres<textarea value={draft.notes} onChange={(event) => setDraft({ ...draft, notes: event.target.value })} placeholder="Informations, souvenirs, sujets à aborder…" /></label>
        <div><button type="button" className="button secondary tiny" onClick={cancel} disabled={saving}>Annuler</button><button className="button primary tiny" disabled={saving}><Save size={14} />{saving ? "Enregistrement…" : "Enregistrer"}</button></div>
      </form>}
    </div>
  </article>;
}

function PlayerFactionCard({ faction, data, contacts, onOpenContact }: { faction: FactionOverview; data: CampaignData; contacts: Contact[]; onOpenContact: (contact: Contact) => void }) {
  const intuitive = data.settings.player_display_mode === "intuitive";
  const progress = Math.min(100, (faction.rp / data.settings.revered_threshold) * 100);
  const access = faction.tension_label === "Rupture" ? "Services suspendus" : unlockedServices(faction.rp, faction.slug, data.settings);
  const services = data.services.filter((service) => service.faction_id === faction.faction_id);
  const highestService = highestAvailableService(services, { ...faction, tension: narrativeTensionValue(faction, data) }, data.settings);
  const relationshipState = intuitive || !data.settings.show_numeric_tension ? faction.tension_label : `Tension ${faction.tension}`;
  const relationshipTone = relationshipToneClass(faction, data);
  return <article className="player-faction-card" style={{ "--accent": faction.accent } as React.CSSProperties}><header><div className="faction-monogram">{faction.short_name.slice(0,2).toUpperCase()}</div><div><p>{faction.domain}</p><h2>{faction.short_name}</h2></div></header><p className="player-description">{faction.public_description}</p>{intuitive ? <><div className="player-appreciation"><small>Appréciation actuelle</small><strong className="status-with-hearts">{faction.status}<ReputationHearts status={faction.status} /></strong></div><div className="player-values"><div><small>Aide envisageable</small><strong className="service-level">{highestService ?? "Improbable"}<ServiceHands scale={highestService} /></strong></div><div className={`relationship-value ${relationshipTone}`}><small>État de la relation</small><RelationshipState label={relationshipState} tone={relationshipTone} /></div></div></> : <><div className="player-rank"><span className="status-with-hearts">{faction.status}<ReputationHearts status={faction.status} /></span><strong>{faction.rp} RP</strong></div><div className="progress-track"><span style={{ width: `${progress}%` }} /></div><div className="player-values"><div><small>Faveurs disponibles</small><strong>{faction.jf} JF</strong></div><div className={`relationship-value ${relationshipTone}`}><small>État de la relation</small><RelationshipState label={relationshipState} tone={relationshipTone} /></div></div><p className="unlock-line">{access}</p></>}{faction.public_summary && <blockquote>{faction.public_summary}</blockquote>}<FactionContactTokens contacts={contacts} onOpen={onOpenContact} /></article>;
}

function FactionContactTokens({ contacts, onOpen }: { contacts: Contact[]; onOpen: (contact: Contact) => void }) {
  if (!contacts.length) return null;
  function nameLines(contact: Contact) {
    if (contact.first_name || contact.last_name) return [contact.first_name, contact.last_name].filter(Boolean) as string[];
    const names = contact.name.trim().split(/\s+/).filter(Boolean);
    return names.length > 1 ? [names[0], names.slice(1).join(" ")] : names;
  }
  return <section className="faction-contact-tokens"><p className="eyebrow">Contacts connus</p><div>{contacts.map((contact) => <button type="button" key={contact.id} className="contact-token" title={`Ouvrir la fiche de ${contact.name}`} onClick={() => onOpen(contact)}><ContactPortrait contact={contact} /><span className="contact-token-name">{nameLines(contact).map((line, index) => <span key={index}>{line}</span>)}</span></button>)}</div></section>;
}

function ContactPortrait({ contact, className = "" }: { contact: Contact; className?: string }) {
  const src = contactPortraitUrl(contact.image_path);
  const zoom = contact.avatar_zoom ?? 1;
  const x = contact.avatar_x ?? 50;
  const y = contact.avatar_y ?? 50;
  const style = { objectPosition: "50% 50%", transform: `translate(${(50 - x) * (zoom - 1)}%, ${(50 - y) * (zoom - 1)}%) scale(${zoom})` };
  return <span className={`contact-portrait ${className}`}>{src ? <img src={src} alt="" style={style} /> : <UserRound size={19} aria-hidden="true" />}</span>;
}

function PlayerContactDialog({ contact, demo, onChanged, onNotice, onError, onClose }: { contact: Contact; demo: boolean; onChanged: () => Promise<void>; onNotice: (message: string) => void; onError: (message: string | null) => void; onClose: () => void }) {
  return <div className="modal-backdrop contact-dialog-backdrop" role="presentation" onClick={onClose}>
    <section className="modal-card player-contact-dialog" role="dialog" aria-modal="true" aria-label={`Fiche de ${contact.name}`} onClick={(event) => event.stopPropagation()}>
      <div className="modal-head">
        <div><p className="eyebrow">{contact.faction_name}</p><h3>{contact.name}</h3></div>
        <button type="button" className="icon-button" onClick={onClose} aria-label="Fermer"><X /></button>
      </div>
      <div className="player-contact-profile">
        <ContactPortrait contact={contact} className="large" />
        <div>
          {contact.role && <p className="contact-role">{contact.role}</p>}
          {contact.attitude && <p className="contact-attitude"><span>Attitude</span>{contact.attitude}</p>}
          {contact.is_primary && <p className="contact-primary-badge"><Check size={14} />Contact principal</p>}
          {contact.public_description && <p className="contact-public-description">{contact.public_description}</p>}
        </div>
      </div>
      <PlayerContactCard contact={contact} demo={demo} onChanged={onChanged} onNotice={onNotice} onError={onError} showIdentity={false} />
    </section>
  </div>;
}

function ReputationHearts({ status }: { status: FactionOverview["status"] }) {
  const count = status === "Révérés" ? 3 : status === "Admirés" ? 2 : status === "Appréciés" ? 1 : 0;
  if (!count) return null;
  return <span className="reputation-hearts" aria-label={`${count} niveau${count > 1 ? "x" : ""} d’appréciation`}>{Array.from({ length: count }, (_, index) => <Heart key={index} size={13} fill="currentColor" aria-hidden="true" />)}</span>;
}

function ServiceHands({ scale }: { scale: string | null }) {
  const count = scale === "Majeure" ? 3 : scale === "Modérée" ? 2 : scale === "Mineure" ? 1 : 0;
  if (!count) return null;
  return <span className="service-hands" aria-label={`${count} niveau${count > 1 ? "x" : ""} de service`}>{Array.from({ length: count }, (_, index) => <Handshake key={index} size={13} aria-hidden="true" />)}</span>;
}

function RelationshipState({ label, tone }: { label: string; tone: string }) {
  const Icon = tone === "is-stable" ? Check : tone === "is-cooling" ? Cloud : tone === "is-tense" ? TriangleAlert : tone === "is-limited" ? LockKeyhole : CircleOff;
  return <strong className={`relationship-state ${tone}`}><Icon size={14} aria-hidden="true" /><span>{label}</span></strong>;
}

function PlayerPolitics({ data, compact = false }: { data: CampaignData; compact?: boolean }) {
  function relation(source: FactionOverview, target: FactionOverview) { return data.relationships.find((item) => item.source_faction_id === source.faction_id && item.target_faction_id === target.faction_id); }
  const hasRelations = data.relationships.length > 0;
  const matrix = hasRelations ? <><p className="section-intro">La matrice se lit par ligne : elle montre comment la première faction considère la seconde. Les relations peuvent être asymétriques.</p><div className="legend-row color-legend"><span><i className="tone-dot favorable" />Favorable</span><span><i className="tone-dot uncertain" />Tendue ou ambiguë</span><span><i className="tone-dot hostile" />Hostile</span></div><div className="matrix-wrap player-matrix"><table className="politics-matrix"><thead><tr><th>Point de vue ↓</th>{data.factions.map((f) => <th key={f.faction_id}>{f.short_name}</th>)}</tr></thead><tbody>{data.factions.map((source) => <tr key={source.faction_id}><th>{source.short_name}</th>{data.factions.map((target) => { const item = relation(source,target); return <td key={target.faction_id} className={source.faction_id === target.faction_id ? "diagonal" : item?.color ?? "unknown"}>{item ? <div><strong>{item.headline}</strong><p>{item.detail}</p></div> : "?"}</td>; })}</tr>)}</tbody></table></div></> : <EmptyState title="Le jeu des factions reste opaque">Les relations révélées par le MJ apparaîtront ici, une direction à la fois.</EmptyState>;
  return compact ? <div className="player-politics-content">{matrix}</div> : <div className="page-stack"><SectionHeading eyebrow="Informations découvertes en jeu" title="Politique connue" />{matrix}</div>;
}


function narrativeTensionValue(faction: FactionOverview, data: CampaignData): number {
  if (data.settings.show_numeric_tension) return faction.tension;
  if (faction.tension_label === "Rupture") return data.settings.tension_max;
  if (faction.tension_label === "Accès limité") return 3;
  if (faction.tension_label === "Relations tendues") return 2;
  if (faction.tension_label === "Signes de froid") return 1;
  return 0;
}

function relationshipToneClass(faction: FactionOverview, data: CampaignData) {
  const tension = narrativeTensionValue(faction, data);
  if (tension >= data.settings.tension_max) return "is-rupture";
  if (tension >= 3) return "is-limited";
  if (tension >= 2) return "is-tense";
  if (tension >= 1) return "is-cooling";
  return "is-stable";
}
