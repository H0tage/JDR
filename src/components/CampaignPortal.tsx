import { CalendarDays, Copy, Crown, Eye, KeyRound, LockKeyhole, LogOut, Mail, Pencil, Plus, Trash2, Users, X } from "lucide-react";
import { useCallback, useEffect, useState, type FormEvent } from "react";
import {
  acceptInvitation,
  createCampaign,
  deleteOwnedCampaign,
  invitationDetails,
  leaveCampaign,
  listMyCampaigns,
  listCampaignMembers,
  sendPasswordRecovery,
  signUp,
  updatePassword,
  updateOwnedCampaign,
  type CampaignMember,
  type CampaignMembership,
  type InvitationDetails,
} from "../lib/campaignPortalApi";
import { currentSession, signInWithPassword, signOut } from "../lib/api";
import { getMyProfile, updateMyProfile, type UserProfile } from "../lib/profileApi";
import { hasSupabaseConfig, supabase } from "../lib/supabase";
import { ErrorPanel, LoadingScreen } from "./ui";

type AuthMode = "sign-in" | "sign-up" | "recovery";

function go(path: string) {
  window.location.assign(path);
}

function rememberInvite(token: string | null) {
  try {
    if (token) window.localStorage.setItem("regalade-pending-invite", token);
    else window.localStorage.removeItem("regalade-pending-invite");
  } catch { /* La navigation reste utilisable sans stockage local. */ }
}

function pendingInvite() {
  try { return window.localStorage.getItem("regalade-pending-invite"); } catch { return null; }
}

function portalDate(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "Date inconnue" : date.toLocaleDateString("fr-FR", { day: "numeric", month: "long", year: "numeric" });
}

export function CampaignPortal() {
  const [sessionReady, setSessionReady] = useState(false);
  const [authenticated, setAuthenticated] = useState(false);

  useEffect(() => {
    void currentSession().then((session) => { setAuthenticated(Boolean(session)); setSessionReady(true); });
    const subscription = supabase?.auth.onAuthStateChange((_event, session) => {
      setAuthenticated(Boolean(session));
      setSessionReady(true);
    });
    return () => subscription?.data.subscription.unsubscribe();
  }, []);

  if (!sessionReady) return <LoadingScreen label="Ouverture du portail…" />;
  return authenticated ? <CampaignList /> : <AuthPanel />;
}

function AuthPanel({ inviteToken, initialMode = "sign-in" }: { inviteToken?: string; initialMode?: AuthMode } = {}) {
  const [mode, setMode] = useState<AuthMode>(initialMode);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true); setError(null); setMessage(null);
    try {
      if (inviteToken) rememberInvite(inviteToken);
      if (mode === "sign-in") {
        await signInWithPassword(email.trim(), password);
        const token = inviteToken ?? pendingInvite();
        go(token ? `/join/${token}` : "/");
      } else if (mode === "sign-up") {
        if (password.length < 8) throw new Error("Le mot de passe doit comporter au moins 8 caractères.");
        if (password !== confirm) throw new Error("Les mots de passe ne correspondent pas.");
        await signUp(email.trim(), password);
        setMessage("Compte créé. Vérifiez votre e-mail pour confirmer votre adresse, puis vous reviendrez ici automatiquement.");
      } else {
        await sendPasswordRecovery(email.trim());
        setMessage("Si cette adresse possède un compte, un lien de récupération vient d’être envoyé.");
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Opération impossible.");
    } finally { setBusy(false); }
  }

  const heading = mode === "sign-in" ? "Se connecter" : mode === "sign-up" ? "Créer un compte" : "Récupérer son mot de passe";
  return <main className="login-shell portal-shell portal-entry"><span className="portal-pillar portal-pillar-left" aria-hidden="true" /><span className="portal-pillar portal-pillar-right" aria-hidden="true" /><section className="login-card portal-card-shell portal-gate">
    <div className="portal-seal" aria-label="Blood Lords"><span>BL</span></div>
    <p className="eyebrow">Blood Lords</p>
    <h1>{mode === "sign-in" ? "Les Registres de Geb" : heading}</h1>
    {mode === "sign-in" && <p className="portal-access-label">Accès aux archives de campagne</p>}
    <p>{mode === "recovery" ? "Indiquez votre adresse e-mail : nous vous enverrons un lien de récupération." : mode === "sign-up" ? "Créez votre identité pour franchir les portes des registres." : "Présentez vos identifiants pour accéder aux campagnes et aux registres de votre groupe."}</p>
    {!hasSupabaseConfig && <ErrorPanel error="Les variables Supabase ne sont pas configurées." />}
    <form className="stack-form" onSubmit={submit}>
      <label>Adresse e-mail<input type="email" required value={email} onChange={(event) => setEmail(event.target.value)} autoComplete="email" /></label>
      {mode !== "recovery" && <label>Mot de passe<input type="password" required value={password} onChange={(event) => setPassword(event.target.value)} autoComplete={mode === "sign-up" ? "new-password" : "current-password"} /></label>}
      {mode === "sign-up" && <label>Confirmer le mot de passe<input type="password" required value={confirm} onChange={(event) => setConfirm(event.target.value)} autoComplete="new-password" /></label>}
      {error && <p className="form-error">{error}</p>}
      {message && <p className="form-success">{message}</p>}
      <button className="button primary" disabled={busy || !hasSupabaseConfig}>{busy ? "Patientez…" : mode === "sign-in" ? "Se connecter" : mode === "sign-up" ? "Créer mon compte" : "Envoyer le lien"}</button>
    </form>
    {!inviteToken && <section className="demo-entry" aria-labelledby="demo-entry-title">
      <p className="eyebrow">Découvrir l’application</p>
      <h2 id="demo-entry-title">Tester le site en mode démo</h2>
      <p>Explorez les deux espaces sans créer de compte.</p>
      <div className="demo-entry-actions">
        <a className="button secondary" href="/MJsecretscreen/?demo=1">Demo MJ</a>
        <a className="button secondary" href="/playerscreen/?demo=1">Demo Joueur</a>
      </div>
    </section>}
    <div className="portal-auth-links">
      {mode !== "sign-in" && <button className="text-button" onClick={() => { setMode("sign-in"); setMessage(null); }}>Déjà un compte ? Se connecter</button>}
      {mode !== "sign-up" && <button className="text-button" onClick={() => { setMode("sign-up"); setMessage(null); }}>Créer un compte</button>}
      {mode !== "recovery" && <button className="text-button" onClick={() => { setMode("recovery"); setMessage(null); }}>Mot de passe oublié ?</button>}
    </div>
  </section></main>;
}

function CampaignList() {
  const [campaigns, setCampaigns] = useState<CampaignMembership[] | null>(null);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [displayName, setDisplayName] = useState("");
  const [editingProfile, setEditingProfile] = useState(false);
  const [savingProfile, setSavingProfile] = useState(false);
  const [creating, setCreating] = useState(false);
  const [campaignName, setCampaignName] = useState("");
  const [campaignDescription, setCampaignDescription] = useState("");
  const [createBusy, setCreateBusy] = useState(false);
  const [campaignToDelete, setCampaignToDelete] = useState<CampaignMembership | null>(null);
  const [deleteConfirmation, setDeleteConfirmation] = useState("");
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [campaignToEdit, setCampaignToEdit] = useState<CampaignMembership | null>(null);
  const [editName, setEditName] = useState("");
  const [editDescription, setEditDescription] = useState("");
  const [editBusy, setEditBusy] = useState(false);
  const [membersByCampaign, setMembersByCampaign] = useState<Record<string, CampaignMember[] | null>>({});
  const [copiedSlug, setCopiedSlug] = useState<string | null>(null);
  const [leavingCampaignId, setLeavingCampaignId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const refresh = useCallback(async () => {
    try {
      const [nextCampaigns, nextProfile] = await Promise.all([listMyCampaigns(), getMyProfile()]);
      const memberEntries = await Promise.all(nextCampaigns.map(async (campaign) => {
        try { return [campaign.campaign_id, await listCampaignMembers(campaign.campaign_id)] as const; }
        catch { return [campaign.campaign_id, null] as const; }
      }));
      setCampaigns(nextCampaigns);
      setMembersByCampaign(Object.fromEntries(memberEntries));
      setProfile(nextProfile);
      setDisplayName(nextProfile.display_name ?? "");
      setEditingProfile(!nextProfile.display_name);
      setError(null);
    }
    catch (caught) { setError(caught instanceof Error ? caught.message : "Impossible de charger vos campagnes."); }
  }, []);
  useEffect(() => { void refresh(); }, [refresh]);
  if (!campaigns && !error) return <LoadingScreen label="Chargement des campagnes…" />;
  async function saveProfile(event: FormEvent) {
    event.preventDefault();
    setSavingProfile(true); setError(null);
    try {
      const next = await updateMyProfile(displayName);
      setProfile(next); setDisplayName(next.display_name ?? ""); setEditingProfile(false);
    } catch (caught) { setError(caught instanceof Error ? caught.message : "Enregistrement du pseudo impossible."); }
    finally { setSavingProfile(false); }
  }
  async function leave(campaign: CampaignMembership) {
    if (!window.confirm(`Quitter « ${campaign.name} » ? Votre page personnelle sera conservée, mais vos butins attribués redeviendront non attribués.`)) return;
    setLeavingCampaignId(campaign.campaign_id); setError(null);
    try {
      await leaveCampaign(campaign.campaign_id);
      setCampaigns((current) => current?.filter((item) => item.campaign_id !== campaign.campaign_id) ?? null);
    } catch (caught) { setError(caught instanceof Error ? caught.message : "Impossible de quitter la campagne."); }
    finally { setLeavingCampaignId(null); }
  }
  async function submitCampaign(event: FormEvent) {
    event.preventDefault();
    setCreateBusy(true); setError(null);
    try {
      const campaign = await createCampaign(campaignName.trim(), campaignDescription.trim());
      go(`/campaign/${campaign.slug}/mj`);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Création de la campagne impossible.");
      setCreateBusy(false);
    }
  }
  async function deleteCampaign() {
    if (!campaignToDelete || deleteConfirmation !== campaignToDelete.name) return;
    setDeleteBusy(true); setError(null);
    try {
      await deleteOwnedCampaign(campaignToDelete.campaign_id);
      setCampaigns((current) => current?.filter((item) => item.campaign_id !== campaignToDelete.campaign_id) ?? null);
      setCampaignToDelete(null); setDeleteConfirmation("");
    } catch (caught) { setError(caught instanceof Error ? caught.message : "Suppression de la campagne impossible."); }
    finally { setDeleteBusy(false); }
  }
  async function saveCampaignDetails(event: FormEvent) {
    event.preventDefault();
    if (!campaignToEdit) return;
    setEditBusy(true); setError(null);
    try {
      const updated = await updateOwnedCampaign(campaignToEdit.campaign_id, editName.trim(), editDescription.trim());
      setCampaigns((current) => current?.map((campaign) => campaign.campaign_id === updated.campaign_id ? { ...campaign, ...updated } : campaign) ?? null);
      setCampaignToEdit(null);
    } catch (caught) { setError(caught instanceof Error ? caught.message : "Modification de la campagne impossible."); }
    finally { setEditBusy(false); }
  }
  async function copyCampaignAddress(campaign: CampaignMembership) {
    try {
      await navigator.clipboard.writeText(`${window.location.origin}/campaign/${campaign.slug}/playerscreen`);
      setCopiedSlug(campaign.slug);
      window.setTimeout(() => setCopiedSlug((current) => current === campaign.slug ? null : current), 1800);
    } catch { setError("Impossible de copier l’adresse de la campagne."); }
  }
  return <main className="portal-page"><header className="portal-header"><div><p className="eyebrow">Les Registres de Geb</p><h1>Mes campagnes</h1><p className="portal-header-summary">{campaigns?.length ?? 0} campagne{campaigns?.length === 1 ? "" : "s"} liée{campaigns?.length === 1 ? "" : "s"} à votre compte</p></div><div className="portal-header-actions">{profile?.display_name && <button className="button primary" onClick={() => setCreating((value) => !value)}><Plus size={17} />Créer une campagne</button>}<button className="button ghost" onClick={() => void signOut().then(() => go("/"))}><LogOut size={17} />Se déconnecter</button></div></header>
    {error && <ErrorPanel error={error} onRetry={() => void refresh()} />}
    <section className="portal-profile"><div><p className="eyebrow">Identité publique</p><h2>{profile?.display_name ?? "Choisissez votre pseudo"}</h2><p>C’est le seul nom visible par votre groupe. Votre adresse e-mail n’est jamais affichée.</p></div>{editingProfile ? <form onSubmit={saveProfile}><label>Pseudo<input required minLength={2} maxLength={40} value={displayName} onChange={(event) => setDisplayName(event.target.value)} autoFocus /></label><div>{profile?.display_name && <button type="button" className="button ghost" onClick={() => { setDisplayName(profile.display_name ?? ""); setEditingProfile(false); }}>Annuler</button>}<button className="button primary" disabled={savingProfile}>{savingProfile ? "Enregistrement…" : "Enregistrer"}</button></div></form> : <button type="button" className="button secondary" onClick={() => setEditingProfile(true)}>Modifier mon pseudo</button>}</section>
    {profile?.display_name && creating && <section className="campaign-create-panel"><div><p className="eyebrow">Nouvelle aventure</p><h2>Créer une campagne</h2><p>Son adresse publique sera composée automatiquement de deux noms de morts-vivants.</p></div><form onSubmit={submitCampaign}><label>Nom de la campagne<input required minLength={2} maxLength={80} value={campaignName} onChange={(event) => setCampaignName(event.target.value)} autoFocus /></label><label>Description <small>(facultative)</small><textarea maxLength={500} value={campaignDescription} onChange={(event) => setCampaignDescription(event.target.value)} /></label><div><button type="button" className="button ghost" onClick={() => setCreating(false)}>Annuler</button><button className="button primary" disabled={createBusy}>{createBusy ? "Création…" : "Créer et ouvrir"}</button></div></form></section>}
    {profile?.display_name && campaigns?.length === 0 && !creating && <section className="portal-empty"><Users size={30} /><h2>Aucune campagne pour le moment</h2><p>Créez votre propre campagne comme MJ ou utilisez le lien envoyé par un maître de jeu pour rejoindre la sienne.</p></section>}
    {profile?.display_name && <section className="campaign-grid">{campaigns?.map((campaign) => {
      const members = membersByCampaign[campaign.campaign_id];
      const players = members?.filter((member) => member.role === "player") ?? [];
      return <article className={`campaign-card ${campaign.is_owner ? "owned" : ""}`} key={campaign.campaign_id}>
        <header className="campaign-card-head"><div><span className={`campaign-role-badge ${campaign.role}`}>{campaign.role === "gm" ? "Maître de jeu" : "Joueur"}</span>{campaign.is_owner && <span className="campaign-owner-badge"><Crown size={13} />Vous êtes propriétaire</span>}</div>{campaign.is_owner && <button type="button" className="campaign-edit-button" onClick={() => { setCampaignToEdit(campaign); setEditName(campaign.name); setEditDescription(campaign.description ?? ""); }}><Pencil size={15} />Modifier</button>}</header>
        <div className="campaign-card-title"><h2>{campaign.name}</h2><p>{campaign.description || "Aucune description pour le moment."}</p></div>
        <dl className="campaign-card-meta"><div><dt><CalendarDays size={15} />Créée le</dt><dd>{portalDate(campaign.created_at)}</dd></div><div><dt>Adresse</dt><dd><code>{campaign.slug}</code><button type="button" aria-label="Copier l’adresse" onClick={() => void copyCampaignAddress(campaign)}><Copy size={14} />{copiedSlug === campaign.slug ? "Copiée" : "Copier"}</button></dd></div></dl>
        <section className="campaign-roster"><div className="campaign-roster-head"><div><Users size={17} /><strong>Joueurs présents</strong></div><span>{members === undefined ? "…" : players.length}</span></div>{members === undefined ? <p className="campaign-roster-empty">Chargement…</p> : members === null ? <p className="campaign-roster-empty">Liste indisponible</p> : players.length === 0 ? <p className="campaign-roster-empty">Aucun joueur n’a encore rejoint cette campagne.</p> : <div className="campaign-player-list">{players.map((member) => <span key={member.user_id}><i>{member.display_name.charAt(0).toLocaleUpperCase()}</i>{member.display_name}</span>)}</div>}</section>
        <footer className="campaign-card-footer"><div className="campaign-primary-actions"><a className="button primary" href={`/campaign/${campaign.slug}/playerscreen`}><Eye size={17} />Écran joueurs</a>{campaign.role === "gm" && <a className="button secondary" href={`/campaign/${campaign.slug}/mj`}><LockKeyhole size={17} />Écran MJ</a>}</div>{campaign.role === "player" ? <button type="button" className="button ghost danger" disabled={leavingCampaignId === campaign.campaign_id} onClick={() => void leave(campaign)}>{leavingCampaignId === campaign.campaign_id ? "Départ…" : "Quitter la campagne"}</button> : campaign.is_owner && <button type="button" className="campaign-delete-link" onClick={() => { setCampaignToDelete(campaign); setDeleteConfirmation(""); }}><Trash2 size={15} />Supprimer la campagne</button>}</footer>
      </article>;
    })}</section>}
    {campaignToEdit && <div className="modal-backdrop"><form className="modal-card campaign-edit-modal" onSubmit={saveCampaignDetails}><div className="modal-head"><div><p className="eyebrow">Détails de la campagne</p><h2>Modifier {campaignToEdit.name}</h2></div><button type="button" className="icon-button" aria-label="Fermer" onClick={() => setCampaignToEdit(null)}><X /></button></div><label>Nom de la campagne<input required minLength={2} maxLength={80} value={editName} onChange={(event) => setEditName(event.target.value)} autoFocus /></label><label>Description <small>(facultative)</small><textarea maxLength={500} value={editDescription} onChange={(event) => setEditDescription(event.target.value)} /></label><p className="campaign-slug-note">L’adresse technique <code>{campaignToEdit.slug}</code> reste inchangée lorsque le nom est modifié.</p><div className="modal-actions"><button type="button" className="button secondary" onClick={() => setCampaignToEdit(null)}>Annuler</button><button className="button primary" disabled={editBusy}>{editBusy ? "Enregistrement…" : "Enregistrer"}</button></div></form></div>}
    {campaignToDelete && <div className="modal-backdrop"><form className="modal-card campaign-delete-modal" onSubmit={(event) => { event.preventDefault(); void deleteCampaign(); }}><div className="modal-head"><div><p className="eyebrow">Action irréversible</p><h2>Supprimer définitivement la campagne ?</h2></div><button type="button" className="icon-button" aria-label="Fermer" onClick={() => setCampaignToDelete(null)}><X /></button></div><p>Tout le contenu de « {campaignToDelete.name} » sera supprimé : membres, pages personnelles, journaux, butins, images et réglages. Son adresse <code>{campaignToDelete.slug}</code> redeviendra disponible.</p><label>Recopiez le nom exact pour confirmer<input required value={deleteConfirmation} onChange={(event) => setDeleteConfirmation(event.target.value)} autoFocus /></label><div className="modal-actions"><button type="button" className="button secondary" onClick={() => setCampaignToDelete(null)}>Annuler</button><button className="button danger" disabled={deleteBusy || deleteConfirmation !== campaignToDelete.name}>{deleteBusy ? "Suppression…" : "Supprimer définitivement"}</button></div></form></div>}
  </main>;
}

export function JoinCampaign({ token }: { token: string }) {
  const [details, setDetails] = useState<InvitationDetails | null | undefined>(undefined);
  const [authenticated, setAuthenticated] = useState(false);
  const [profile, setProfile] = useState<UserProfile | null | undefined>(undefined);
  const [displayName, setDisplayName] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    rememberInvite(token);
    void invitationDetails(token).then(setDetails).catch((caught) => { setError(caught instanceof Error ? caught.message : "Invitation introuvable."); setDetails(null); });
    void currentSession().then(async (session) => {
      setAuthenticated(Boolean(session));
      if (!session) return;
      try {
        const currentProfile = await getMyProfile();
        setProfile(currentProfile);
        setDisplayName(currentProfile.display_name ?? "");
      } catch (caught) {
        setError(caught instanceof Error ? caught.message : "Profil indisponible.");
        setProfile(null);
      }
    });
  }, [token]);
  if (details === undefined) return <LoadingScreen label="Vérification de l’invitation…" />;
  if (!details || details.status !== "valid") return <main className="login-shell portal-shell"><section className="login-card portal-card-shell"><div className="login-mark"><KeyRound size={24} /></div><p className="eyebrow">Invitation</p><h1>Invitation indisponible</h1><p>{details?.status === "expired" ? "Cette invitation a expiré." : details?.status === "revoked" ? "Cette invitation a été révoquée." : error ?? "Ce lien est invalide."}</p><a className="button secondary" href="/">Retour au portail</a></section></main>;
  if (!authenticated) return <InviteWelcome details={details} token={token} />;
  if (profile === undefined) return <LoadingScreen label="Préparation de votre profil…" />;
  async function accept() {
    setBusy(true); setError(null);
    try {
      if (!profile?.display_name) setProfile(await updateMyProfile(displayName));
      const joined = await acceptInvitation(token);
      rememberInvite(null);
      // Le RPC d’acceptation conserve son contrat historique ; on récupère
      // ensuite le slug pour éviter de rediriger vers l’ancienne URL UUID.
      const campaign = (await listMyCampaigns()).find((item) => item.campaign_id === joined.campaign_id);
      go(`/campaign/${campaign?.slug ?? joined.campaign_id}/playerscreen`);
    } catch (caught) { setError(caught instanceof Error ? caught.message : "Impossible de rejoindre cette campagne."); setBusy(false); }
  }
  return <main className="login-shell portal-shell"><section className="login-card portal-card-shell"><div className="login-mark"><Users size={24} /></div><p className="eyebrow">Invitation à rejoindre</p><h1>{details.campaign_name}</h1><p>Vous êtes sur le point de rejoindre cette campagne en tant que joueur.</p>{!profile?.display_name && <label className="invite-display-name">Votre pseudo public<input required minLength={2} maxLength={40} value={displayName} onChange={(event) => setDisplayName(event.target.value)} placeholder="Visible par le groupe, jamais votre e-mail" /></label>}{error && <p className="form-error">{error}</p>}<button className="button primary" disabled={busy || (!profile?.display_name && displayName.trim().length < 2)} onClick={() => void accept()}>{busy ? "Ajout en cours…" : "Rejoindre la campagne"}</button><a className="back-link" href="/">Retour à mes campagnes</a></section></main>;
}

function InviteWelcome({ details, token }: { details: InvitationDetails; token: string }) {
  return <main className="login-shell portal-shell"><section className="login-card portal-card-shell"><div className="login-mark"><Mail size={24} /></div><p className="eyebrow">Vous avez été invité à rejoindre</p><h1>{details.campaign_name}</h1><div className="invite-auth-options"><div><h2>Nouveau sur Regalade JDR ?</h2><p>Créez un compte pour rejoindre cette campagne.</p><InviteAction token={token} mode="sign-up" label="Créer un compte" /></div><div><h2>Déjà un compte ?</h2><p>Connectez-vous pour rejoindre cette campagne.</p><InviteAction token={token} mode="sign-in" label="Se connecter" /></div></div></section></main>;
}

function InviteAction({ token, mode, label }: { token: string; mode: AuthMode; label: string }) {
  return <a className="button secondary" href={`/?invite=${encodeURIComponent(token)}&auth=${mode}`}>{label}</a>;
}

export function PasswordRecovery() {
  const [password, setPassword] = useState(""); const [confirm, setConfirm] = useState(""); const [busy, setBusy] = useState(false); const [message, setMessage] = useState<string | null>(null); const [error, setError] = useState<string | null>(null);
  async function submit(event: FormEvent) { event.preventDefault(); setBusy(true); setError(null); try { if (password.length < 8) throw new Error("Le mot de passe doit comporter au moins 8 caractères."); if (password !== confirm) throw new Error("Les mots de passe ne correspondent pas."); await updatePassword(password); setMessage("Mot de passe modifié. Vous pouvez maintenant accéder à vos campagnes."); } catch (caught) { setError(caught instanceof Error ? caught.message : "Modification impossible."); } finally { setBusy(false); } }
  return <main className="login-shell portal-shell"><section className="login-card portal-card-shell"><div className="login-mark"><KeyRound size={24} /></div><p className="eyebrow">Sécurité du compte</p><h1>Nouveau mot de passe</h1><form className="stack-form" onSubmit={submit}><label>Nouveau mot de passe<input type="password" value={password} onChange={(event) => setPassword(event.target.value)} required autoComplete="new-password" /></label><label>Confirmer le mot de passe<input type="password" value={confirm} onChange={(event) => setConfirm(event.target.value)} required autoComplete="new-password" /></label>{error && <p className="form-error">{error}</p>}{message && <p className="form-success">{message}</p>}<button className="button primary" disabled={busy}>{busy ? "Enregistrement…" : "Enregistrer le mot de passe"}</button></form>{message && <a className="back-link" href="/">Mes campagnes</a>}</section></main>;
}

export function AuthCallback() {
  useEffect(() => {
    if (new URLSearchParams(window.location.search).get("type") === "recovery") { go("/reset-password"); return; }
    const subscription = supabase?.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY") { go("/reset-password"); return; }
      const token = pendingInvite();
      if (token) go(`/join/${token}`); else go("/");
    });
    window.setTimeout(() => { const token = pendingInvite(); go(token ? `/join/${token}` : "/"); }, 1600);
    return () => subscription?.data.subscription.unsubscribe();
  }, []);
  return <LoadingScreen label="Connexion en cours…" />;
}

export function PortalWithInvite({ token, auth }: { token?: string; auth?: AuthMode }) {
  if (!token) return <CampaignPortal />;
  rememberInvite(token);
  return <AuthPanel inviteToken={token} initialMode={auth ?? "sign-in"} key={auth} />;
}
