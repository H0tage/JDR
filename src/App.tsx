import { Suspense, useEffect, useState } from "react";
import { AuthCallback, CampaignPortal, JoinCampaign, PasswordRecovery, PortalWithInvite } from "./components/CampaignPortal";
import { GmApp } from "./components/GmApp";
import { PlayerApp } from "./components/PlayerApp";
import { listMyCampaigns, type CampaignMembership } from "./lib/campaignPortalApi";
import { currentSession } from "./lib/api";
import { ErrorPanel, LoadingScreen } from "./components/ui";

const DEMO_CAMPAIGN_ID = "00000000-0000-4000-8000-000000000001";

function LoadedApp({ children }: { children: React.ReactNode }) {
  return <Suspense fallback={<LoadingScreen label="Chargement de l’application…" />}>{children}</Suspense>;
}

function routePath() {
  const redirected = new URLSearchParams(window.location.search).get("route");
  return (redirected ? redirected.split("?")[0] : window.location.pathname).replace(/\/+$/, "") || "/";
}

function titleForPath(path: string, demo = false) {
  const normalizedPath = path.toLowerCase();
  if (normalizedPath === "/mjsecretscreen" || /\/campaign\/[a-z0-9-]+\/mj$/i.test(path)) return `Écran MJ${demo ? " · Demo" : ""}`;
  if (normalizedPath === "/playerscreen" || /\/campaign\/[a-z0-9-]+\/playerscreen$/i.test(path)) return `Écran Joueurs${demo ? " · Demo" : ""}`;
  return "Les Registres de Geb";
}

function CampaignRoute({ campaignRef, view }: { campaignRef: string; view: "player" | "gm" }) {
  const [membership, setMembership] = useState<CampaignMembership | null | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    void (async () => {
      const session = await currentSession();
      if (!session) { window.location.assign("/"); return; }
      try {
        const memberships = await listMyCampaigns();
        const normalizedRef = campaignRef.toLowerCase();
        setMembership(memberships.find((candidate) => candidate.campaign_id.toLowerCase() === normalizedRef || candidate.slug.toLowerCase() === normalizedRef) ?? null);
      } catch (caught) { setError(caught instanceof Error ? caught.message : "Accès à la campagne impossible."); setMembership(null); }
    })();
  }, [campaignRef]);
  if (membership === undefined) return <LoadingScreen label="Vérification de la campagne…" />;
  if (!membership) return <main className="state-screen"><ErrorPanel error={error ?? "Cette campagne est inaccessible ou n’existe pas."} /><a className="button secondary" href="/">Mes campagnes</a></main>;
  if (view === "gm" && membership.role !== "gm") return <main className="state-screen"><ErrorPanel error="Cet espace est réservé au maître de jeu de cette campagne." /><a className="button secondary" href={`/campaign/${membership.slug}/playerscreen`}>Ouvrir la vue joueurs</a></main>;
  return (
    <LoadedApp>
      {view === "gm" ? <GmApp campaignId={membership.campaign_id} campaignSlug={membership.slug} /> : <PlayerApp campaignId={membership.campaign_id} campaignSlug={membership.slug} viewerRole={membership.role} />}
    </LoadedApp>
  );
}

export function App() {
  const path = routePath();
  const normalizedPath = path.toLowerCase();
  const query = new URLSearchParams(window.location.search);
  const campaign = path.match(/^\/campaign\/([a-z0-9-]+)\/(playerscreen|mj)$/i);
  const invite = path.match(/^\/join\/([0-9a-f-]{36})$/i);
  const demo = query.get("demo") === "1";
  useEffect(() => {
    document.title = titleForPath(path, demo);
  }, [path, demo]);
  if (campaign) return <CampaignRoute campaignRef={campaign[1]} view={campaign[2] === "mj" ? "gm" : "player"} />;
  if (invite) return <JoinCampaign token={invite[1]} />;
  if (path === "/auth/callback") return <AuthCallback />;
  if (path === "/reset-password") return <PasswordRecovery />;
  if (demo && normalizedPath === "/playerscreen") {
    return <LoadedApp><PlayerApp campaignId={DEMO_CAMPAIGN_ID} viewerRole="player" /></LoadedApp>;
  }
  if (demo && normalizedPath === "/mjsecretscreen") {
    return <LoadedApp><GmApp campaignId={DEMO_CAMPAIGN_ID} /></LoadedApp>;
  }
  if (normalizedPath === "/playerscreen" || normalizedPath === "/mjsecretscreen") return <CampaignPortal />;
  if (query.get("invite")) return <PortalWithInvite token={query.get("invite") ?? undefined} auth={query.get("auth") === "sign-up" ? "sign-up" : "sign-in"} />;
  return <CampaignPortal />;
}
