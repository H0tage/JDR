import { useCallback, useEffect, useMemo, useState, type CSSProperties, type FormEvent, type ReactNode } from "react";
import {
  ArrowDownToLine, ArrowRightLeft, ArrowUpFromLine, Banknote, Check, ChevronDown,
  CircleDollarSign, Coins, Gem, GitBranch, HandCoins, History, LayoutGrid, PackageOpen,
  List, ListChecks, Plus, ReceiptText, RefreshCw, Scissors, Send, ShoppingBag, Trash2, WalletCards, X,
} from "lucide-react";
import {
  assignInventoryItem, batchUpdateInventoryItems, cancelItemEvent, cancelItemRequest, cancelMoneyTransaction,
  createManualInventoryItem, createMoneyDebt, dismantleInventoryItem, formatCopper,
  loadPlayerEconomy, mergeInventoryItems, moneyToCp, payMoneyDebt, purchaseInventoryItem, recordCommonIncome,
  recordPersonalMoney, requestInventoryItem, resolveItemRequest, returnInventoryItem,
  sellInventoryItem, setInventoryItemTerminal, splitInventoryItem, transferMoney,
  type MoneyUnit,
} from "../lib/playerEconomyApi";
import { listCampaignPlayers, type CampaignPlayer } from "../lib/profileApi";
import type { CampaignInventoryItem, CampaignItemEvent, CampaignMoneyTransaction, PlayerEconomyData } from "../lib/types";
import { EmptyState, ErrorPanel, LoadingScreen, SectionHeading } from "./ui";

type InventorySection = "common" | "mine" | "others" | "activity";
type ItemAction = "sell" | "split" | "merge" | "dismantle" | "terminal" | "history" | null;
type MoneyAction = "transfer" | "personal" | "purchase" | "debt" | "common-income" | "manual-item" | null;
type SummaryDisplay = "compact" | "large";

function storedSummaryDisplay(): SummaryDisplay {
  try {
    return window.localStorage.getItem("blood-lords-economy-summary-display") === "compact" ? "compact" : "large";
  } catch {
    return "large";
  }
}

export function PlayerEconomyTab({ campaignId, demo, viewerRole }: { campaignId: string; demo: boolean; viewerRole: "player" | "gm" }) {
  const [data, setData] = useState<PlayerEconomyData | null>(null);
  const [players, setPlayers] = useState<CampaignPlayer[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [section, setSection] = useState<InventorySection>("common");
  const [moneyAction, setMoneyAction] = useState<MoneyAction>(null);
  const [selectedItem, setSelectedItem] = useState<CampaignInventoryItem | null>(null);
  const [itemAction, setItemAction] = useState<ItemAction>(null);
  const [saving, setSaving] = useState(false);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [mobileInventoryUserId, setMobileInventoryUserId] = useState("");
  const [summaryDisplay, setSummaryDisplay] = useState<SummaryDisplay>(storedSummaryDisplay);

  const refresh = useCallback(async () => {
    try {
      const [economy, campaignPlayers] = await Promise.all([
        loadPlayerEconomy(campaignId, demo),
        listCampaignPlayers(campaignId, demo),
      ]);
      setData(economy);
      setPlayers(campaignPlayers);
      setError(null);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Chargement de l’économie impossible.");
    }
  }, [campaignId, demo]);

  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => {
    if (demo) return;
    const interval = window.setInterval(() => void refresh(), 15_000);
    return () => window.clearInterval(interval);
  }, [demo, refresh]);
  useEffect(() => { setSelectedIds([]); }, [section]);
  useEffect(() => {
    try { window.localStorage.setItem("blood-lords-economy-summary-display", summaryDisplay); }
    catch { /* Le choix reste actif pour la session si le stockage est bloqué. */ }
  }, [summaryDisplay]);
  useEffect(() => {
    const visiblePlayers = players.filter((player) => viewerRole === "gm" || player.user_id !== data?.viewer_user_id);
    setMobileInventoryUserId((current) => visiblePlayers.some((player) => player.user_id === current) ? current : visiblePlayers[0]?.user_id ?? "");
  }, [data?.viewer_user_id, players, viewerRole]);

  async function execute(operation: () => Promise<unknown>, success: string) {
    setSaving(true);
    try {
      if (!demo) await operation();
      setNotice(demo ? `${success} — simulation` : success);
      setError(null);
      setMoneyAction(null);
      setSelectedItem(null);
      setItemAction(null);
      if (!demo) await refresh();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Opération impossible.");
    } finally {
      setSaving(false);
    }
  }

  async function cancelOutgoingRequest(requestId: string) {
    setSaving(true);
    try {
      if (!demo) await cancelItemRequest(requestId);
      setData((current) => {
        if (!current) return current;
        const cancelledItemId = current.requests.find((request) => request.id === requestId)?.item_id;
        return {
          ...current,
          requests: current.requests.map((request) => request.id === requestId
            ? { ...request, status: "cancelled", resolved_at: new Date().toISOString() }
            : request),
          items: current.items.map((item) => item.id === cancelledItemId
            ? { ...item, requested_by_me: false, pending_request_count: Math.max(0, item.pending_request_count - 1) }
            : item),
        };
      });
      setNotice(demo ? "Demande annulée. — simulation" : "Demande annulée.");
      setError(null);
      if (!demo) await refresh();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Annulation impossible.");
    } finally {
      setSaving(false);
    }
  }

  if (!data) return error ? <ErrorPanel error={error} onRetry={() => void refresh()} /> : <LoadingScreen label="Ouverture de la trésorerie…" />;

  const viewerUserId = data.viewer_user_id;
  const activeItems = data.items.filter((item) => item.status === "active");
  const commonItems = activeItems.filter((item) => item.owner_user_id === null);
  const myItems = activeItems.filter((item) => item.owner_user_id === data.viewer_user_id);
  const otherItems = activeItems.filter((item) => item.owner_user_id !== null && item.owner_user_id !== data.viewer_user_id);
  const commonBalance = data.balances.find((balance) => balance.is_common)?.balance_cp ?? 0;
  const personalBalances = data.balances.filter((balance) => !balance.is_common);
  const myBalance = data.balances.find((balance) => balance.account_user_id === data.viewer_user_id)?.balance_cp ?? 0;
  const displayedPersonalBalance = viewerRole === "gm" ? personalBalances.reduce((total, balance) => total + balance.balance_cp, 0) : myBalance;
  const commonStock = commonItems.reduce((total, item) => total + (item.unit_value_cp ?? 0) * item.quantity, 0);
  const currentWealth = data.totals.current_wealth_cp;
  const totalEntered = data.totals.total_entered_cp;
  const totalExited = data.totals.total_exited_cp;
  const incomingRequests = data.requests.filter((request) => request.status === "pending" && request.owner_user_id === data.viewer_user_id);
  const outgoingRequests = data.requests.filter((request) => request.status === "pending" && request.requester_user_id === data.viewer_user_id);
  const groupInventoryPlayers = players.filter((player) => viewerRole === "gm" || player.user_id !== data.viewer_user_id);

  const visibleItems = section === "common" ? commonItems : myItems;

  function openItemAction(item: CampaignInventoryItem, action: ItemAction) {
    setSelectedItem(item);
    setItemAction(action);
    setMoneyAction(null);
  }

  function renderInventoryCard(item: CampaignInventoryItem, showOwner = true) {
    return <InventoryCard key={item.id} item={item} allItems={activeItems} viewerId={viewerUserId} viewerRole={viewerRole} players={players} saving={saving} selected={selectedIds.includes(item.id)} showOwner={showOwner} onToggleSelected={() => setSelectedIds((current) => current.includes(item.id) ? current.filter((id) => id !== item.id) : [...current, item.id])} onOpenAction={openItemAction} onExecute={execute} />;
  }

  return <div className="page-stack player-economy">
    <div className="economy-heading">
      <SectionHeading eyebrow="Inventaire et trésorerie" title="Butins" />
      <div className="economy-heading-actions"><fieldset className="economy-display-picker"><legend>Affichage du résumé</legend><button type="button" className={summaryDisplay === "compact" ? "active" : ""} aria-pressed={summaryDisplay === "compact"} onClick={() => setSummaryDisplay("compact")}><List size={15} />Compact</button><button type="button" className={summaryDisplay === "large" ? "active" : ""} aria-pressed={summaryDisplay === "large"} onClick={() => setSummaryDisplay("large")}><LayoutGrid size={15} />Large</button></fieldset><button className="icon-button" type="button" title="Actualiser" onClick={() => void refresh()}><RefreshCw size={17} /></button></div>
    </div>
    {notice && <p className="economy-notice"><Check size={15} />{notice}<button type="button" onClick={() => setNotice(null)}><X size={13} /></button></p>}
    {error && <p className="player-loot-save-error" role="alert">{error}</p>}

    <div className={`economy-summary economy-summary-${summaryDisplay}`}>
      <section className="economy-metrics" aria-label="Résumé de la trésorerie">
        <article><span><Coins size={17} />Compte commun</span><strong>{formatCopper(commonBalance)}</strong><small>or disponible</small></article>
        <article><span><WalletCards size={17} />{viewerRole === "gm" ? "Comptes joueurs" : "Mon compte"}</span><strong>{formatCopper(displayedPersonalBalance)}</strong><small>{viewerRole === "gm" ? "total détaillé ci-dessous" : "les soldes négatifs sont autorisés"}</small></article>
        <article><span><PackageOpen size={17} />Stock commun</span><strong>{formatCopper(commonStock)}</strong><small>{commonItems.length} objet{commonItems.length > 1 ? "s" : ""} à répartir</small></article>
        <article><span><CircleDollarSign size={17} />Patrimoine actuel</span><strong>{formatCopper(currentWealth)}</strong><small>ensemble des comptes et objets chiffrés</small></article>
        <article><span><ArrowDownToLine size={17} />Entré depuis le début</span><strong>{formatCopper(totalEntered)}</strong><small>butins, achats et revenus</small></article>
        <article><span><ArrowUpFromLine size={17} />Sorti depuis le début</span><strong>{formatCopper(totalExited)}</strong><small>dépenses, pertes et consommation</small></article>
      </section>

      {(viewerRole === "gm" || personalBalances.length > 1) && <section className="economy-player-balances panel" aria-label="Soldes personnels visibles">
        <header><WalletCards size={18} /><div><h2>Comptes personnels</h2><small>{viewerRole === "gm" ? "Vue complète du MJ" : "Visibilité autorisée par le MJ"}</small></div></header>
        <div>{personalBalances.map((balance) => <article key={balance.account_user_id}><span>{balance.display_name}</span><strong className={balance.balance_cp < 0 ? "negative" : ""}>{formatCopper(balance.balance_cp)}</strong></article>)}</div>
      </section>}
    </div>

    <section className="economy-actions" aria-label="Actions financières">
      <button type="button" onClick={() => setMoneyAction("transfer")}><ArrowRightLeft size={17} /><span>Transférer</span></button>
      <button type="button" onClick={() => setMoneyAction("personal")}><HandCoins size={17} /><span>Revenu ou dépense</span></button>
      {viewerRole === "player" && <button type="button" onClick={() => setMoneyAction("purchase")}><ShoppingBag size={17} /><span>Achat boutique</span></button>}
      <button type="button" disabled={players.length < 2} title={players.length < 2 ? "Deux joueurs sont nécessaires" : undefined} onClick={() => setMoneyAction("debt")}><ReceiptText size={17} /><span>Déclarer une dette</span></button>
      {viewerRole === "gm" && <button type="button" onClick={() => setMoneyAction("common-income")}><ArrowDownToLine size={17} /><span>Entrée commune</span></button>}
      {viewerRole === "gm" && <button type="button" onClick={() => setMoneyAction("manual-item")}><Plus size={17} /><span>Créer un objet</span></button>}
    </section>

    {moneyAction && <MoneyActionPanel action={moneyAction} data={data} players={players} saving={saving} onClose={() => setMoneyAction(null)} onExecute={execute} campaignId={campaignId} viewerRole={viewerRole} />}

    {(incomingRequests.length > 0 || outgoingRequests.length > 0) && <section className="economy-requests panel">
      <header><div><Send size={18} /><h2>Demandes d’objets</h2></div><span>{incomingRequests.length + outgoingRequests.length}</span></header>
      <div>
        {incomingRequests.map((request) => <article key={request.id}><div><strong>{request.requester_display_name}</strong><span>demande {request.item_name}</span></div><div><button className="button tiny primary" disabled={saving} onClick={() => void execute(() => resolveItemRequest(request.id, true), "Objet envoyé.")}>Accepter</button><button className="button tiny secondary" disabled={saving} onClick={() => void execute(() => resolveItemRequest(request.id, false), "Demande refusée.")}>Refuser</button></div></article>)}
        {outgoingRequests.map((request) => <article key={request.id}><div><strong>{request.item_name}</strong><span>demande envoyée à {request.owner_display_name}</span></div><button className="button tiny secondary" disabled={saving} onClick={() => void cancelOutgoingRequest(request.id)}>Annuler</button></article>)}
      </div>
    </section>}

    <nav className="economy-sections" aria-label="Sections de l’inventaire">
      <button className={section === "common" ? "active" : ""} onClick={() => setSection("common")}>Compte commun <span>{commonItems.length}</span></button>
      <button className={section === "mine" ? "active" : ""} onClick={() => setSection("mine")}>Mes objets <span>{myItems.length}</span></button>
      <button className={section === "others" ? "active" : ""} onClick={() => setSection("others")}>Inventaires du groupe <span>{otherItems.length}</span></button>
      <button className={section === "activity" ? "active" : ""} onClick={() => setSection("activity")}><History size={15} />Activité</button>
    </nav>

    {section !== "activity" && selectedIds.length > 0 && <BatchActionBar count={selectedIds.length} players={players} saving={saving} onClear={() => setSelectedIds([])} onApply={(action, targetUserId, comment) => void execute(async () => { await batchUpdateInventoryItems(selectedIds, action, targetUserId, comment); setSelectedIds([]); }, `${selectedIds.length} objet${selectedIds.length > 1 ? "s" : ""} mis à jour.`)} />}

    {section === "activity" ? <EconomyActivity data={data} saving={saving} onExecute={execute} />
      : section === "others" ? <GroupInventories players={groupInventoryPlayers} items={otherItems} mobilePlayerId={mobileInventoryUserId} onMobilePlayer={setMobileInventoryUserId} renderItem={(item) => renderInventoryCard(item, false)} />
        : visibleItems.length > 0 ? <section className="economy-item-grid">{visibleItems.map((item) => renderInventoryCard(item))}</section>
          : <EmptyState title={section === "common" ? "Le compte commun est vide" : "Aucun objet personnel"}>Les objets apparaîtront ici au fil de leur attribution.</EmptyState>}

    {selectedItem && itemAction && <ItemActionPanel item={selectedItem} action={itemAction} mergeCandidates={activeItems.filter((candidate) => candidate.id !== selectedItem.id && candidate.name === selectedItem.name && candidate.owner_user_id === selectedItem.owner_user_id && candidate.unit_value_cp === selectedItem.unit_value_cp && candidate.aon_legacy_url === selectedItem.aon_legacy_url)} events={data.item_history.filter((event) => event.item_id === selectedItem.id || event.related_item_id === selectedItem.id)} saving={saving} onClose={() => { setSelectedItem(null); setItemAction(null); }} onExecute={execute} />}

    {data.debts.some((debt) => debt.status === "open") && <section className="economy-debts panel"><header><ReceiptText size={18} /><h2>Dettes en cours</h2></header>{data.debts.filter((debt) => debt.status === "open").map((debt) => <article key={debt.id}><div><strong>{debt.debtor_display_name} doit {formatCopper(debt.remaining_cp)} à {debt.creditor_display_name}</strong>{debt.comment && <small>{debt.comment}</small>}</div>{debt.debtor_user_id === data.viewer_user_id && <button className="button tiny secondary" disabled={saving} onClick={() => void execute(() => payMoneyDebt(debt.id, debt.remaining_cp), "Dette remboursée." )}>Rembourser</button>}</article>)}</section>}
  </div>;
}

function GroupInventories({ players, items, mobilePlayerId, onMobilePlayer, renderItem }: { players: CampaignPlayer[]; items: CampaignInventoryItem[]; mobilePlayerId: string; onMobilePlayer: (userId: string) => void; renderItem: (item: CampaignInventoryItem) => ReactNode }) {
  if (players.length === 0) return <EmptyState title="Aucun autre joueur">Les inventaires apparaîtront ici lorsque d’autres joueurs auront rejoint la campagne.</EmptyState>;
  return <section className="economy-group-inventories-wrap">
    <label className="economy-group-mobile-picker">Inventaire affiché<select value={mobilePlayerId} onChange={(event) => onMobilePlayer(event.target.value)}>{players.map((player) => <option key={player.user_id} value={player.user_id}>{player.display_name}</option>)}</select></label>
    <div className="economy-group-inventories" style={{ "--inventory-column-count": Math.min(players.length, 5) } as CSSProperties}>
      {players.map((player) => {
        const playerItems = items.filter((item) => item.owner_user_id === player.user_id);
        const itemCount = playerItems.reduce((total, item) => total + item.quantity, 0);
        return <article key={player.user_id} className={`economy-player-inventory${player.user_id === mobilePlayerId ? " mobile-active" : ""}`}>
          <header><div><UserInventoryIcon /><div><h2>{player.display_name}</h2><small>{formatQuantity(itemCount)} objet{itemCount !== 1 ? "s" : ""}</small></div></div></header>
          <div>{playerItems.length > 0 ? playerItems.map(renderItem) : <p className="economy-empty-inventory">Inventaire vide</p>}</div>
        </article>;
      })}
    </div>
  </section>;
}

function UserInventoryIcon() {
  return <WalletCards size={18} aria-hidden="true" />;
}

function BatchActionBar({ count, players, saving, onClear, onApply }: { count: number; players: CampaignPlayer[]; saving: boolean; onClear: () => void; onApply: (action: "assign" | "return" | "consumed" | "lost" | "donated", targetUserId: string | null, comment: string) => void }) {
  const [action, setAction] = useState<"assign" | "return" | "consumed" | "lost" | "donated">("assign");
  const [target, setTarget] = useState(players[0]?.user_id ?? "");
  const [comment, setComment] = useState("");
  return <section className="economy-batch-bar" aria-label="Action groupée">
    <div><ListChecks size={18} /><strong>{count} objet{count > 1 ? "s" : ""} sélectionné{count > 1 ? "s" : ""}</strong></div>
    <select aria-label="Action groupée" value={action} onChange={(event) => setAction(event.target.value as typeof action)}><option value="assign">Attribuer à…</option><option value="return">Remettre au compte commun</option><option value="consumed">Marquer consommé</option><option value="lost">Marquer perdu</option><option value="donated">Donné hors du groupe</option></select>
    {action === "assign" && <select aria-label="Destinataire groupé" value={target} onChange={(event) => setTarget(event.target.value)}>{players.map((player) => <option key={player.user_id} value={player.user_id}>{player.display_name}</option>)}</select>}
    <input aria-label="Commentaire groupé facultatif" value={comment} maxLength={500} onChange={(event) => setComment(event.target.value)} placeholder="Commentaire facultatif" />
    <button className="button tiny primary" type="button" disabled={saving || (action === "assign" && !target)} onClick={() => onApply(action, action === "assign" ? target : null, comment)}>Appliquer</button>
    <button className="icon-button" type="button" title="Annuler la sélection" onClick={onClear}><X size={15} /></button>
  </section>;
}

function InventoryCard({ item, allItems, viewerId, viewerRole, players, saving, selected, showOwner = true, onToggleSelected, onOpenAction, onExecute }: { item: CampaignInventoryItem; allItems: CampaignInventoryItem[]; viewerId: string; viewerRole: "player" | "gm"; players: CampaignPlayer[]; saving: boolean; selected: boolean; showOwner?: boolean; onToggleSelected: () => void; onOpenAction: (item: CampaignInventoryItem, action: ItemAction) => void; onExecute: (operation: () => Promise<unknown>, success: string) => Promise<void> }) {
  const isCommon = item.owner_user_id === null;
  const isMine = item.owner_user_id === viewerId;
  const controllable = viewerRole === "gm" || isCommon || isMine;
  const canMerge = allItems.some((candidate) => candidate.id !== item.id && candidate.name === item.name && candidate.owner_user_id === item.owner_user_id && candidate.unit_value_cp === item.unit_value_cp && candidate.aon_legacy_url === item.aon_legacy_url);
  return <article className={`economy-item-card${selected ? " selected" : ""}`}>
    <header><div>{controllable && <label className="economy-item-selector" title="Sélectionner pour une action groupée"><input type="checkbox" checked={selected} onChange={onToggleSelected} /><ListChecks size={16} /></label>}<Gem size={19} /><div><h2>{item.name}</h2>{showOwner && <small>{item.owner_display_name ?? "Compte commun"}</small>}</div></div>{item.quantity !== 1 && <span>× {formatQuantity(item.quantity)}</span>}</header>
    <div className="economy-item-value"><span>Valeur unitaire</span><strong>{formatCopper(item.unit_value_cp)}</strong>{item.aon_legacy_url && <a href={item.aon_legacy_url} target="_blank" rel="noreferrer">AoN</a>}</div>
    {item.pending_request_count > 0 && <p className="economy-item-requests">{item.pending_request_count} demande{item.pending_request_count > 1 ? "s" : ""} en attente</p>}
    <footer>
      {controllable && <select aria-label={`Attribuer ${item.name}`} value="" disabled={saving} onChange={(event) => {
        const target = event.target.value;
        if (target === "common") void onExecute(() => returnInventoryItem(item.id), "Objet remis au compte commun.");
        else if (target) void onExecute(() => assignInventoryItem(item.id, target), "Objet attribué.");
      }}><option value="">Attribuer…</option>{isMine && <option value="common">Compte commun</option>}{players.map((player) => <option key={player.user_id} value={player.user_id}>{player.user_id === viewerId ? "Moi" : player.display_name}</option>)}</select>}
      {controllable ? <details><summary><ChevronDown size={15} />Actions</summary><div>{item.quantity > 1 && <button type="button" onClick={() => onOpenAction(item, "split")}>Fractionner</button>}{canMerge && <button type="button" onClick={() => onOpenAction(item, "merge")}>Regrouper</button>}<button type="button" onClick={() => onOpenAction(item, "sell")}>Vendre</button><button type="button" onClick={() => onOpenAction(item, "dismantle")}>Démonter</button><button type="button" onClick={() => onOpenAction(item, "terminal")}>Consommer / sortir</button><button type="button" onClick={() => onOpenAction(item, "history")}>Historique</button></div></details> : <>{item.requested_by_me ? <span className="request-sent">Demande envoyée</span> : <button className="button tiny secondary" disabled={saving} onClick={() => void onExecute(() => requestInventoryItem(item.id), "Demande envoyée.")}>Demander</button>}<button className="icon-button" type="button" title="Historique" onClick={() => onOpenAction(item, "history")}><History size={15} /></button></>}
    </footer>
  </article>;
}

function MoneyActionPanel({ action, data, players, saving, onClose, onExecute, campaignId, viewerRole }: { action: MoneyAction; data: PlayerEconomyData; players: CampaignPlayer[]; saving: boolean; onClose: () => void; onExecute: (operation: () => Promise<unknown>, success: string) => Promise<void>; campaignId: string; viewerRole: "player" | "gm" }) {
  const defaultPlayerId = players.find((player) => player.user_id === data.viewer_user_id)?.user_id ?? players[0]?.user_id ?? "";
  const [amount, setAmount] = useState("0");
  const [unit, setUnit] = useState<MoneyUnit>("gp");
  const [comment, setComment] = useState("");
  const [kind, setKind] = useState<"income" | "expense">("income");
  const [source, setSource] = useState<string>(viewerRole === "gm" && action === "transfer" ? "common" : defaultPlayerId);
  const [destination, setDestination] = useState<string>(viewerRole === "gm" && action === "transfer" ? defaultPlayerId : "common");
  const [name, setName] = useState("");
  const [quantity, setQuantity] = useState("1");
  const [commonShare, setCommonShare] = useState("0");
  const [aonName, setAonName] = useState("");
  const [aonUrl, setAonUrl] = useState("");
  const [debtor, setDebtor] = useState(defaultPlayerId);
  const [creditor, setCreditor] = useState(players.find((player) => player.user_id !== defaultPlayerId)?.user_id ?? "");
  const amountCp = moneyToCp(Number(amount) || 0, unit);
  const commonCp = moneyToCp(Number(commonShare) || 0, unit);
  const allAccounts = [{ user_id: "common", display_name: "Compte commun" }, ...players];

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (action === "transfer") await onExecute(() => transferMoney(campaignId, source === "common" ? null : source, destination === "common" ? null : destination, amountCp, comment), "Transfert enregistré.");
    if (action === "personal") await onExecute(() => recordPersonalMoney(campaignId, kind, amountCp, comment, viewerRole === "gm" ? source : undefined), kind === "income" ? "Revenu ajouté." : "Dépense ajoutée.");
    if (action === "common-income") await onExecute(() => recordCommonIncome(campaignId, amountCp, comment), "Entrée ajoutée au compte commun.");
    if (action === "purchase") await onExecute(() => purchaseInventoryItem({ campaignId, name, quantity: Number(quantity) || 1, priceCp: amountCp, personalAmountCp: amountCp - commonCp, commonAmountCp: commonCp, ownerUserId: viewerRole === "gm" ? destination : undefined, aonName, aonUrl, comment }), "Achat enregistré.");
    if (action === "manual-item") await onExecute(() => createManualInventoryItem({ campaignId, name, quantity: Number(quantity) || 1, unitValueCp: amountCp || null, ownerUserId: destination === "common" ? null : destination, aonName, aonUrl, comment }), "Objet créé.");
    if (action === "debt") await onExecute(() => createMoneyDebt(campaignId, debtor, creditor, amountCp, comment), "Dette enregistrée.");
  }

  const title = { transfer: "Transférer de l’or", personal: "Revenu ou dépense personnelle", purchase: "Achat boutique", debt: "Déclarer une dette", "common-income": "Ajouter une entrée commune", "manual-item": "Créer un objet" }[action ?? "transfer"];
  return <form className="economy-action-panel panel" onSubmit={(event) => void submit(event)}>
    <header><div><Banknote size={19} /><h2>{title}</h2></div><button type="button" className="icon-button" onClick={onClose}><X size={16} /></button></header>
    <div className="economy-action-fields">
      {(action === "purchase" || action === "manual-item") && <label>Objet<input required value={name} onChange={(event) => setName(event.target.value)} placeholder="Nom de l’objet" /></label>}
      {(action === "purchase" || action === "manual-item") && <label>Quantité<input type="number" min="1" step="1" value={quantity} onChange={(event) => setQuantity(event.target.value)} /></label>}
      {(action === "purchase" || action === "manual-item") && <label>Nom Archive of Nethys <small>facultatif</small><input value={aonName} onChange={(event) => setAonName(event.target.value)} placeholder="Nom anglais de la référence" /></label>}
      {(action === "purchase" || action === "manual-item") && <label>Lien Archive of Nethys <small>facultatif</small><input type="url" value={aonUrl} onChange={(event) => setAonUrl(event.target.value)} placeholder="https://2e.aonprd.com/…" /></label>}
      {action === "personal" && <label>Opération<select value={kind} onChange={(event) => setKind(event.target.value as "income" | "expense")}><option value="income">Revenu</option><option value="expense">Dépense</option></select></label>}
      {action === "transfer" && <label>Depuis<select value={source} onChange={(event) => { const next = event.target.value; setSource(next); if (destination === next) setDestination(allAccounts.find((account) => account.user_id !== next)?.user_id ?? ""); }}>{allAccounts.filter((account) => account.user_id === "common" || account.user_id === data.viewer_user_id || viewerRole === "gm").map((account) => <option key={account.user_id} value={account.user_id}>{account.display_name}</option>)}</select></label>}
      {action === "transfer" && <label>Vers<select value={destination} onChange={(event) => setDestination(event.target.value)}>{allAccounts.filter((account) => account.user_id !== source).map((account) => <option key={account.user_id} value={account.user_id}>{account.display_name}</option>)}</select></label>}
      {action === "personal" && viewerRole === "gm" && <label>Compte<select value={source} onChange={(event) => setSource(event.target.value)}>{players.map((player) => <option key={player.user_id} value={player.user_id}>{player.display_name}</option>)}</select></label>}
      {action === "manual-item" && <label>Propriétaire<select value={destination} onChange={(event) => setDestination(event.target.value)}>{allAccounts.map((account) => <option key={account.user_id} value={account.user_id}>{account.display_name}</option>)}</select></label>}
      {action === "purchase" && viewerRole === "gm" && <label>Acheteur<select value={destination} onChange={(event) => setDestination(event.target.value)}>{players.map((player) => <option key={player.user_id} value={player.user_id}>{player.display_name}</option>)}</select></label>}
      {action === "debt" && <><label>Débiteur<select value={debtor} onChange={(event) => { const next = event.target.value; setDebtor(next); if (creditor === next) setCreditor(players.find((player) => player.user_id !== next)?.user_id ?? ""); }}>{players.map((player) => <option key={player.user_id} value={player.user_id}>{player.display_name}</option>)}</select></label><label>Créancier<select value={creditor} onChange={(event) => setCreditor(event.target.value)}>{players.filter((player) => player.user_id !== debtor).map((player) => <option key={player.user_id} value={player.user_id}>{player.display_name}</option>)}</select></label></>}
      <MoneyField label={action === "manual-item" ? "Valeur unitaire" : "Montant"} amount={amount} unit={unit} onAmount={setAmount} onUnit={setUnit} />
      {action === "purchase" && <label>Part payée par le compte commun<input type="number" min="0" max={Number(amount) || 0} step="0.01" value={commonShare} onChange={(event) => setCommonShare(event.target.value)} /><small>Le reste sera pris sur le compte de l’acheteur. La valeur de l’objet sera égale au prix payé.</small></label>}
      <label className="span-2">Commentaire <small>facultatif</small><input value={comment} maxLength={500} onChange={(event) => setComment(event.target.value)} placeholder="Ex. remboursement de la chambre" /></label>
    </div>
    <footer><button type="button" className="button secondary" onClick={onClose}>Annuler</button><button className="button primary" disabled={saving || (action !== "manual-item" && amountCp <= 0) || (action === "purchase" && commonCp > amountCp)}>{saving ? "Enregistrement…" : "Confirmer"}</button></footer>
  </form>;
}

function ItemActionPanel({ item, action, mergeCandidates, events, saving, onClose, onExecute }: { item: CampaignInventoryItem; action: ItemAction; mergeCandidates: CampaignInventoryItem[]; events: CampaignItemEvent[]; saving: boolean; onClose: () => void; onExecute: (operation: () => Promise<unknown>, success: string) => Promise<void> }) {
  const [quantity, setQuantity] = useState(String(item.quantity));
  const [amount, setAmount] = useState(item.unit_value_cp === null ? "0" : String(item.unit_value_cp * item.quantity / 100));
  const [unit, setUnit] = useState<MoneyUnit>("gp");
  const [comment, setComment] = useState("");
  const [terminal, setTerminal] = useState<"consumed" | "lost" | "donated">("consumed");
  const [outputs, setOutputs] = useState([{ name: "", quantity: "1", value: "0", unit: "gp" as MoneyUnit, aonUrl: "" }]);
  const [mergeSource, setMergeSource] = useState(mergeCandidates[0]?.id ?? "");
  const quantityNumber = Number(quantity) || 0;

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (action === "sell") await onExecute(() => sellInventoryItem(item.id, quantityNumber, moneyToCp(Number(amount) || 0, unit), comment), "Vente enregistrée dans le compte commun.");
    if (action === "split") await onExecute(() => splitInventoryItem(item.id, quantityNumber), "Pile fractionnée.");
    if (action === "merge") await onExecute(() => mergeInventoryItems(item.id, mergeSource), "Piles regroupées.");
    if (action === "terminal") await onExecute(() => setInventoryItemTerminal(item.id, terminal, quantityNumber, comment), "Objet mis à jour.");
    if (action === "dismantle") await onExecute(() => dismantleInventoryItem(item.id, outputs.map((output) => ({ name: output.name, quantity: Number(output.quantity) || 1, unit_value_cp: output.value ? moneyToCp(Number(output.value), output.unit) : null, aon_legacy_url: output.aonUrl || undefined })), comment), "Objet démonté.");
  }

  if (action === "history") return <section className="economy-action-panel economy-item-history panel"><header><div><History size={19} /><h2>Histoire de {item.name}</h2></div><button className="icon-button" type="button" onClick={onClose}><X size={16} /></button></header><EventTimeline events={events} /><footer><button className="button secondary" type="button" onClick={onClose}>Fermer</button></footer></section>;

  return <form className="economy-action-panel panel" onSubmit={(event) => void submit(event)}>
    <header><div>{action === "dismantle" ? <Scissors size={19} /> : action === "sell" ? <Coins size={19} /> : <GitBranch size={19} />}<h2>{action === "sell" ? `Vendre ${item.name}` : action === "split" ? `Fractionner ${item.name}` : action === "merge" ? `Regrouper ${item.name}` : action === "dismantle" ? `Démonter ${item.name}` : `Sortir ${item.name}`}</h2></div><button type="button" className="icon-button" onClick={onClose}><X size={16} /></button></header>
    <div className="economy-action-fields">
      {action !== "dismantle" && action !== "merge" && <label>Quantité<input type="number" min="0.0001" max={item.quantity} step="0.0001" value={quantity} onChange={(event) => setQuantity(event.target.value)} /></label>}
      {action === "merge" && <label className="span-2">Pile à regrouper<select required value={mergeSource} onChange={(event) => setMergeSource(event.target.value)}>{mergeCandidates.map((candidate) => <option key={candidate.id} value={candidate.id}>{formatQuantity(candidate.quantity)} × {candidate.name}</option>)}</select></label>}
      {action === "sell" && <MoneyField label="Prix total de vente" amount={amount} unit={unit} onAmount={setAmount} onUnit={setUnit} />}
      {action === "terminal" && <label>État<select value={terminal} onChange={(event) => setTerminal(event.target.value as typeof terminal)}><option value="consumed">Consommé</option><option value="lost">Perdu</option><option value="donated">Donné hors du groupe</option></select></label>}
      {action === "dismantle" && <div className="dismantle-outputs span-2"><span>Objets obtenus</span>{outputs.map((output, index) => <div key={index}><input required value={output.name} onChange={(event) => setOutputs((current) => current.map((entry, entryIndex) => entryIndex === index ? { ...entry, name: event.target.value } : entry))} placeholder="Nom de l’objet" /><input type="number" min="0.0001" step="0.0001" value={output.quantity} onChange={(event) => setOutputs((current) => current.map((entry, entryIndex) => entryIndex === index ? { ...entry, quantity: event.target.value } : entry))} aria-label="Quantité obtenue" /><input type="number" min="0" step="0.01" value={output.value} onChange={(event) => setOutputs((current) => current.map((entry, entryIndex) => entryIndex === index ? { ...entry, value: event.target.value } : entry))} aria-label="Valeur unitaire" /><select value={output.unit} onChange={(event) => setOutputs((current) => current.map((entry, entryIndex) => entryIndex === index ? { ...entry, unit: event.target.value as MoneyUnit } : entry))}><option value="gp">po</option><option value="sp">pa</option><option value="cp">pc</option></select>{outputs.length > 1 && <button type="button" className="icon-button" onClick={() => setOutputs((current) => current.filter((_entry, entryIndex) => entryIndex !== index))}><Trash2 size={14} /></button>}<input className="dismantle-aon" type="url" value={output.aonUrl} onChange={(event) => setOutputs((current) => current.map((entry, entryIndex) => entryIndex === index ? { ...entry, aonUrl: event.target.value } : entry))} placeholder="Lien Archive of Nethys (facultatif)" /></div>)}<button type="button" className="button tiny secondary" onClick={() => setOutputs((current) => [...current, { name: "", quantity: "1", value: "0", unit: "gp", aonUrl: "" }])}><Plus size={14} />Ajouter un résultat</button></div>}
      {action !== "split" && action !== "merge" && <label className="span-2">Commentaire <small>facultatif</small><input maxLength={500} value={comment} onChange={(event) => setComment(event.target.value)} /></label>}
    </div>
    <footer><button className="button secondary" type="button" onClick={onClose}>Annuler</button><button className="button primary" disabled={saving || (action === "merge" ? !mergeSource : quantityNumber <= 0 || quantityNumber > item.quantity)}>{saving ? "Enregistrement…" : "Confirmer"}</button></footer>
  </form>;
}

function EconomyActivity({ data, saving, onExecute }: { data: PlayerEconomyData; saving: boolean; onExecute: (operation: () => Promise<unknown>, success: string) => Promise<void> }) {
  const [filter, setFilter] = useState("");
  const cancelledMoneyIds = useMemo(() => new Set(data.money_history.flatMap((entry) => entry.reversed_transaction_id ? [entry.reversed_transaction_id] : [])), [data.money_history]);
  const cancelledItemEventIds = useMemo(() => new Set(data.item_history.flatMap((entry) => entry.reversed_event_id ? [entry.reversed_event_id] : [])), [data.item_history]);
  const itemOperationIds = useMemo(() => new Set(data.item_history.flatMap((entry) => entry.money_operation_id ? [entry.money_operation_id] : [])), [data.item_history]);
  const entries = useMemo(() => [
    ...data.money_history.filter((entry) => !itemOperationIds.has(entry.operation_id)).map((entry) => ({ date: entry.created_at, kind: "money" as const, entry })),
    ...data.item_history.map((entry) => ({ date: entry.created_at, kind: "item" as const, entry })),
  ].sort((first, second) => second.date.localeCompare(first.date)).filter((row) => describeActivity(row.entry).toLowerCase().includes(filter.toLowerCase())), [data, filter, itemOperationIds]);
  return <section className="economy-activity panel"><header><div><History size={18} /><h2>Journal des opérations</h2></div><input type="search" value={filter} onChange={(event) => setFilter(event.target.value)} placeholder="Joueur, objet, commentaire…" /></header><div>{entries.length ? entries.map((row) => {
    const cancelled = row.kind === "money" ? cancelledMoneyIds.has(row.entry.id) : cancelledItemEventIds.has(row.entry.id);
    return <article key={`${row.kind}-${row.entry.id}`} className={cancelled ? "cancelled" : undefined}><time>{formatDateTime(row.date)}</time><div><strong>{describeActivity(row.entry)}</strong>{row.entry.comment && <small>{row.entry.comment}</small>}</div>{cancelled ? <span className="economy-cancelled-label">Action annulée</span> : <>{row.kind === "money" && canCancelMoney(row.entry, data.viewer_user_id) && <button className="button tiny secondary" disabled={saving} onClick={() => void onExecute(() => cancelMoneyTransaction(row.entry.id), "Opération annulée.")}>Annuler</button>}{row.kind === "item" && row.entry.event_type === "sold" && row.entry.actor_user_id === data.viewer_user_id && <button className="button tiny secondary" disabled={saving} onClick={() => void onExecute(() => cancelItemEvent(row.entry.id), "Vente annulée.")}>Annuler la vente</button>}</>}</article>;
  }) : <p className="empty-state">Aucune opération correspondante.</p>}</div></section>;
}

function EventTimeline({ events }: { events: CampaignItemEvent[] }) {
  const sorted = [...events].sort((first, second) => first.created_at.localeCompare(second.created_at));
  return <div className="item-timeline">{sorted.length ? sorted.map((event) => <article key={event.id}><time>{formatDateTime(event.created_at)}</time><div><strong>{describeItemEvent(event)}</strong>{event.comment && <small>{event.comment}</small>}</div></article>) : <p className="empty-state">Aucun événement enregistré.</p>}</div>;
}

function MoneyField({ label, amount, unit, onAmount, onUnit }: { label: string; amount: string; unit: MoneyUnit; onAmount: (value: string) => void; onUnit: (value: MoneyUnit) => void }) {
  return <label>{label}<span className="money-input"><input type="number" min="0" step="0.01" value={amount} onChange={(event) => onAmount(event.target.value)} /><select value={unit} onChange={(event) => onUnit(event.target.value as MoneyUnit)}><option value="gp">po</option><option value="sp">pa</option><option value="cp">pc</option></select></span></label>;
}

function describeActivity(entry: CampaignMoneyTransaction | CampaignItemEvent) {
  if ("source_account" in entry) {
    const source = entry.source_account === "common" ? "le compte commun" : entry.source_account === "player" ? entry.source_display_name ?? "un joueur" : "l’extérieur";
    const destination = entry.destination_account === "common" ? "le compte commun" : entry.destination_account === "player" ? entry.destination_display_name ?? "un joueur" : "l’extérieur";
    if (entry.kind === "sale") return `${entry.actor_display_name ?? "Un joueur"} a vendu ${entry.related_item_name ?? "un objet"} pour ${formatCopper(entry.amount_cp)}`;
    if (entry.kind === "purchase") return `${entry.actor_display_name ?? "Un joueur"} a acheté ${entry.related_item_name ?? "un objet"} pour ${formatCopper(entry.amount_cp)}`;
    return `${entry.reversed_transaction_id ? "Suite à annulation : " : ""}${formatCopper(entry.amount_cp)} : ${source} → ${destination}`;
  }
  return `${entry.reversed_event_id ? "Suite à annulation : " : ""}${describeItemEvent(entry)}`;
}

function describeItemEvent(event: CampaignItemEvent) {
  const actor = event.actor_display_name ?? "Le système";
  const target = event.next_owner_display_name ?? "le compte commun";
  return {
    created: `${actor} a créé ${event.item_name ?? "l’objet"}`,
    published: `${event.item_name ?? "L’objet"} est entré dans l’inventaire`,
    claimed: `${actor} a pris ${event.item_name ?? "l’objet"}`,
    transferred: `${actor} a envoyé ${event.item_name ?? "l’objet"} à ${target}`,
    returned: `${actor} a remis ${event.item_name ?? "l’objet"} dans le compte commun`,
    split: `${actor} a fractionné ${event.item_name ?? "l’objet"}`,
    merged: `${actor} a regroupé ${event.item_name ?? "l’objet"}`,
    sold: `${actor} a vendu ${event.item_name ?? "l’objet"} pour ${formatCopper(event.value_cp)}`,
    sale_cancelled: `${actor} a annulé la vente de ${event.item_name ?? "l’objet"}`,
    purchased: `${actor} a acheté ${event.item_name ?? "l’objet"} pour ${formatCopper(event.value_cp)}`,
    dismantled: `${actor} a démonté ${event.item_name ?? "l’objet"}`,
    consumed: `${actor} a consommé ${event.item_name ?? "l’objet"}`,
    lost: `${actor} a perdu ${event.item_name ?? "l’objet"}`,
    donated: `${actor} a donné ${event.item_name ?? "l’objet"} hors du groupe`,
  }[event.event_type];
}

function canCancelMoney(entry: CampaignMoneyTransaction, viewerId: string) {
  return entry.actor_user_id === viewerId && !["sale", "purchase", "reversal", "departure_transfer"].includes(entry.kind) && !entry.reversed_transaction_id;
}

function formatQuantity(value: number) { return Number.isInteger(value) ? String(value) : String(value).replace(".", ","); }
function formatDateTime(value: string) { return new Date(value).toLocaleString("fr-FR", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }); }
