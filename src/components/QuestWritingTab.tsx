import { Bold, ChevronDown, ChevronRight, CircleAlert, CornerDownLeft, History, ImagePlus, IndentDecrease, IndentIncrease, Italic, Link, List, Lock, Redo2, Save, Settings2, SmilePlus, Trash2, Undo2, Unlock, X } from "lucide-react";
import { useEffect, useMemo, useRef, useState, type CSSProperties, type FormEvent, type KeyboardEvent, type MouseEvent } from "react";
import { loadQuestJournalPage, QuestJournalVersionConflictError, restoreQuestJournalRevision, saveQuestJournalPage, uploadQuestJournalImage } from "../lib/api";
import { deleteJournalDraft, readJournalDraft, writeJournalDraft, type JournalDraft } from "../lib/journalDrafts";
import type { QuestJournalPage, QuestJournalRevision } from "../lib/types";
import { SectionHeading } from "./ui";

type Props = { page: QuestJournalPage; revisions?: QuestJournalRevision[]; canRestoreHistory?: boolean; demo: boolean; onChanged: () => Promise<void> | void; onNotice: (message: string) => void; onError: (message: string | null) => void; };
type SessionLink = { id: string; label: string };
type ActiveSession = SessionLink & { locked: boolean; date: string };
type JournalPreferences = { font: string; size: number; headingFont: string; h2: number; h3: number; h4: number; h5: number; lineHeight: number; indent: number; };

const journalFonts = [
  { value: "Helvetica Neue", label: "Helvetica Neue" }, { value: "Futura", label: "Futura" }, { value: "Univers", label: "Univers" },
  { value: "Source Serif 4", label: "Source Serif 4" }, { value: "Literata", label: "Literata" }, { value: "Alegreya", label: "Alegreya" },
  { value: "Atkinson Hyperlegible", label: "Atkinson Hyperlegible" }, { value: "Inter", label: "Inter" }, { value: "Cinzel Decorative", label: "Cinzel Decorative" },
] as const;
const defaultPreferences: JournalPreferences = { font: "Source Serif 4", size: 16, headingFont: "Cinzel Decorative", h2: 25, h3: 21, h4: 18, h5: 16, lineHeight: 1.75, indent: 22 };
const preferenceKey = "blood-lords-quest-journal-preferences";
const emojis = ["⚔️", "🧭", "📜", "🔍", "🗝️", "🩸", "💀", "🧟", "🧛", "🦴", "🔥", "❄️", "⚡", "☠️", "❗", "❓", "✅", "🛡️", "🏰", "🕯️", "🗺️", "👁️", "🤝", "💰"];
const compactJournalQuery = "(max-width: 680px)";

function readPreferences(): JournalPreferences { try { return { ...defaultPreferences, ...(JSON.parse(window.localStorage.getItem(preferenceKey) ?? "{}") as Partial<JournalPreferences>) }; } catch { return defaultPreferences; } }
function isCompactJournalViewport() { return typeof window !== "undefined" && window.matchMedia?.(compactJournalQuery).matches === true; }
function sessionParts(label: string) { const [date, ...rest] = label.split(" · "); return rest.length > 0 ? { date, title: rest.join(" · ") } : { date: "", title: date }; }
function todayLabel() { return new Date().toLocaleDateString("fr-CH", { day: "2-digit", month: "2-digit", year: "2-digit" }); }
function todayInput() { const now = new Date(); return new Date(now.getTime() - now.getTimezoneOffset() * 60_000).toISOString().slice(0, 10); }
function dateInputFromLabel(label: string) { const match = /^(\d{2})\.(\d{2})\.(\d{2}|\d{4})$/.exec(sessionParts(label).date); return match ? `${match[3].length === 2 ? `20${match[3]}` : match[3]}-${match[2]}-${match[1]}` : null; }
function formatSessionDate(value: string) { const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value); return match ? `${match[3]}.${match[2]}.${match[1].slice(-2)}` : todayLabel(); }
function line(): HTMLParagraphElement { const result = document.createElement("p"); result.append(document.createElement("br")); return result; }
function setCaret(target: Node, atEnd = true) { const selection = window.getSelection(); const range = document.createRange(); range.selectNodeContents(target); range.collapse(atEnd); selection?.removeAllRanges(); selection?.addRange(range); }
function sessionDate(section: HTMLDetailsElement) { return section.querySelector<HTMLElement>(".journal-session-date")?.dataset.sessionDate ?? "9999-12-31"; }
function topLevelChild(canvas: HTMLElement, element: Element | null) { let current = element; while (current?.parentElement && current.parentElement !== canvas) current = current.parentElement; return current?.parentElement === canvas ? current : null; }
function sessionsFromContent(content: string): SessionLink[] { const body = new DOMParser().parseFromString(content, "text/html").body; return Array.from(body.querySelectorAll<HTMLDetailsElement>("details[data-session-id]")).map((section) => ({ id: section.dataset.sessionId ?? "", label: section.querySelector("summary")?.textContent?.trim() || "Séance sans titre" })).filter((entry) => entry.id && entry.label !== "Séance sans titre"); }
function activeSessionFromContent(content: string, id: string | null): ActiveSession | null { if (!id) return null; const body = new DOMParser().parseFromString(content, "text/html").body; const section = body.querySelector<HTMLDetailsElement>(`details[data-session-id="${id}"]`); if (!section) return null; const label = section.querySelector("summary")?.textContent?.trim() || "Séance sans titre"; return { id, label, locked: section.dataset.locked === "true", date: section.querySelector<HTMLElement>(".journal-session-date")?.dataset.sessionDate || dateInputFromLabel(label) || todayInput() }; }

function sanitizeContent(value: string): string {
  const body = new DOMParser().parseFromString(value, "text/html").body;
  const allowed = new Set(["P", "DIV", "SPAN", "BR", "STRONG", "B", "EM", "I", "S", "UL", "OL", "LI", "A", "FONT", "IMG", "H2", "H3", "H4", "H5", "BLOCKQUOTE", "HR", "DETAILS", "SUMMARY", "BUTTON"]);
  for (const node of Array.from(body.querySelectorAll("script, style, iframe, object, embed"))) node.remove();
  for (const element of Array.from(body.querySelectorAll("*"))) {
    if (!allowed.has(element.tagName)) { element.replaceWith(...Array.from(element.childNodes)); continue; }
    for (const attribute of Array.from(element.attributes)) {
      const hrefAllowed = element.tagName === "A" && attribute.name === "href" && /^(https?:|mailto:|\/)/i.test(attribute.value.trim());
      const imageAllowed = element.tagName === "IMG" && ["src", "alt"].includes(attribute.name) && (attribute.name !== "src" || /^(https?:|blob:)/i.test(attribute.value.trim()));
      const sessionAllowed = element.tagName === "DETAILS" && ["data-session-id", "data-locked", "open"].includes(attribute.name);
      const calloutAllowed = element.tagName === "DIV" && attribute.name === "data-callout-id";
      const indentationAllowed = ["P", "DIV", "H2", "H3", "H4", "H5", "UL", "OL", "BLOCKQUOTE"].includes(element.tagName) && attribute.name === "data-indent" && /^\d$/.test(attribute.value);
      const sessionHeaderAllowed = element.tagName === "SPAN" && ["data-session-date", "contenteditable"].includes(attribute.name);
      const fontAllowed = element.tagName === "FONT" && ((attribute.name === "face" && journalFonts.some((font) => font.value === attribute.value)) || (attribute.name === "size" && /^[1-7]$/.test(attribute.value)));
      const classAllowed = attribute.name === "class" && ["journal-callout", "journal-divider", "journal-callout-delete", "journal-session-toggle", "journal-session-date", "journal-session-separator", "journal-session-title", "journal-inline-image"].includes(attribute.value);
      const calloutButtonAllowed = element.tagName === "BUTTON" && ["type", "contenteditable", "aria-label", "tabindex"].includes(attribute.name);
      if (!hrefAllowed && !imageAllowed && !sessionAllowed && !calloutAllowed && !indentationAllowed && !sessionHeaderAllowed && !fontAllowed && !classAllowed && !calloutButtonAllowed) element.removeAttribute(attribute.name);
    }
    if (element.tagName === "A" && element.getAttribute("href")) { element.setAttribute("target", "_blank"); element.setAttribute("rel", "noreferrer"); }
  }
  return body.innerHTML;
}

export function QuestWritingTab({ page, revisions = [], canRestoreHistory = false, demo, onChanged, onNotice, onError }: Props) {
  const canvasRef = useRef<HTMLDivElement | null>(null);
  const uploadInputRef = useRef<HTMLInputElement | null>(null);
  const saveTimer = useRef<number | null>(null);
  const saveInFlight = useRef(false);
  const pendingContent = useRef<string | null>(null);
  const latestContent = useRef(page.content);
  const confirmedContent = useRef(page.content);
  const serverRevision = useRef(page.revision ?? 0);
  const [content, setContent] = useState(page.content);
  const [status, setStatus] = useState<"saved" | "dirty" | "saving" | "conflict">("saved");
  const [activeSessionId, setActiveSessionId] = useState<string | null>(null);
  const [activeCalloutId, setActiveCalloutId] = useState<string | null>(null);
  const [deleteCandidate, setDeleteCandidate] = useState<SessionLink | null>(null);
  const [preferences, setPreferences] = useState<JournalPreferences>(readPreferences);
  const [showPreferences, setShowPreferences] = useState(false);
  const [showEmojiPicker, setShowEmojiPicker] = useState(false);
  const [showHistory, setShowHistory] = useState(false);
  const [localRecovery, setLocalRecovery] = useState<JournalDraft | null>(null);
  const [conflictContent, setConflictContent] = useState<string | null>(null);
  const [compactJournal, setCompactJournal] = useState(isCompactJournalViewport);
  const [navigatorOpen, setNavigatorOpen] = useState(() => !isCompactJournalViewport());
  const [toolbarOpen, setToolbarOpen] = useState(() => !isCompactJournalViewport());
  const sessions = useMemo(() => sessionsFromContent(content), [content]);
  const activeSession = useMemo(() => activeSessionFromContent(content, activeSessionId), [content, activeSessionId]);
  const canvasStyle = { "--journal-font": `"${preferences.font}", Georgia, serif`, "--journal-size": `${preferences.size}px`, "--journal-heading-font": `"${preferences.headingFont}", Georgia, serif`, "--journal-h2": `${preferences.h2}px`, "--journal-h3": `${preferences.h3}px`, "--journal-h4": `${preferences.h4}px`, "--journal-h5": `${preferences.h5}px`, "--journal-line-height": String(preferences.lineHeight), "--journal-indent": `${preferences.indent}px` } as CSSProperties;

  useEffect(() => {
    if (demo) return;
    let cancelled = false;
    void readJournalDraft(page.campaign_id).then((draft) => {
      if (cancelled || !draft) return;
      if (draft.content !== page.content) setLocalRecovery(draft);
      else void deleteJournalDraft(page.campaign_id);
    });
    return () => { cancelled = true; };
  }, [demo, page.campaign_id]);
  useEffect(() => {
    if (demo || saveInFlight.current || pendingContent.current !== null || conflictContent !== null) return;
    const remoteRevision = page.revision ?? 0;
    if (remoteRevision < serverRevision.current) return;
    if (remoteRevision === serverRevision.current && page.content === confirmedContent.current) return;
    serverRevision.current = remoteRevision;
    confirmedContent.current = page.content;
    latestContent.current = page.content;
    const canvas = canvasRef.current;
    if (canvas && canvas.innerHTML !== page.content) { canvas.innerHTML = page.content; normalizeCanvas(canvas); }
    setContent(page.content);
  }, [conflictContent, demo, page.content, page.revision]);
  useEffect(() => () => { if (saveTimer.current) window.clearTimeout(saveTimer.current); }, []);
  useEffect(() => {
    const warnBeforeLeaving = (event: BeforeUnloadEvent) => { if (status === "saved") return; event.preventDefault(); event.returnValue = ""; };
    window.addEventListener("beforeunload", warnBeforeLeaving);
    return () => window.removeEventListener("beforeunload", warnBeforeLeaving);
  }, [status]);
  useEffect(() => {
    const media = window.matchMedia?.(compactJournalQuery); if (!media) return;
    const updateCompactLayout = () => { setCompactJournal(media.matches); setNavigatorOpen(!media.matches); setToolbarOpen(!media.matches); };
    updateCompactLayout(); media.addEventListener?.("change", updateCompactLayout);
    return () => media.removeEventListener?.("change", updateCompactLayout);
  }, []);
  useEffect(() => { window.localStorage.setItem(preferenceKey, JSON.stringify(preferences)); }, [preferences]);
  useEffect(() => { const canvas = canvasRef.current; if (canvas && document.activeElement !== canvas && canvas.innerHTML !== content) { canvas.innerHTML = content; normalizeCanvas(canvas); } }, [content]);
  useEffect(() => { const canvas = canvasRef.current; if (!canvas) return; for (const section of Array.from(canvas.querySelectorAll<HTMLDetailsElement>("details[data-session-id]"))) section.classList.toggle("active-session", section.dataset.sessionId === activeSessionId); for (const callout of Array.from(canvas.querySelectorAll<HTMLElement>(".journal-callout"))) callout.classList.toggle("active-callout", callout.dataset.calloutId === activeCalloutId); }, [content, activeSessionId, activeCalloutId]);

  function storeLocalCopy(nextContent: string) {
    void writeJournalDraft({ campaignId: page.campaign_id, content: nextContent, revision: serverRevision.current, savedAt: Date.now() });
  }
  async function persistQueuedContent() {
    if (saveInFlight.current || conflictContent !== null) return;
    const nextContent = pendingContent.current;
    if (nextContent === null) return;
    pendingContent.current = null;
    saveInFlight.current = true;
    setStatus("saving");
    let saved = false;
    try {
      const safeContent = sanitizeContent(nextContent);
      const revision = demo
        ? serverRevision.current + 1
        : await saveQuestJournalPage({ campaign_id: page.campaign_id, content: safeContent, revision: serverRevision.current });
      serverRevision.current = revision;
      confirmedContent.current = safeContent;
      storeLocalCopy(latestContent.current);
      if (!demo) await onChanged();
      saved = true;
      setStatus(pendingContent.current === null ? "saved" : "dirty");
    } catch (caught) {
      if (caught instanceof QuestJournalVersionConflictError) {
        const protectedCopy = latestContent.current;
        pendingContent.current = null;
        storeLocalCopy(protectedCopy);
        setConflictContent(protectedCopy);
        setStatus("conflict");
        onError(null);
      } else {
        pendingContent.current = latestContent.current;
        setStatus("dirty");
        onError(caught instanceof Error ? caught.message : "Journal de quête impossible à enregistrer.");
      }
    } finally {
      saveInFlight.current = false;
      if (saved && pendingContent.current !== null) void persistQueuedContent();
    }
  }
  function updateContent(nextContent: string) {
    latestContent.current = nextContent;
    pendingContent.current = nextContent;
    setContent(nextContent);
    setStatus("dirty");
    onError(null);
    storeLocalCopy(nextContent);
    if (saveTimer.current) window.clearTimeout(saveTimer.current);
    saveTimer.current = window.setTimeout(() => { saveTimer.current = null; void persistQueuedContent(); }, 900);
  }
  function ensureSelection() { const canvas = canvasRef.current; if (!canvas) return false; canvas.focus(); const selection = window.getSelection(); if (!selection || !selection.rangeCount || !canvas.contains(selection.anchorNode)) setCaret(canvas); return true; }
  function selectedElement() { const node = window.getSelection()?.anchorNode; return node instanceof Element ? node : node?.parentElement ?? null; }
  function currentSession() { return selectedElement()?.closest<HTMLDetailsElement>("details[data-session-id]") ?? null; }
  function currentCallout() { return selectedElement()?.closest<HTMLElement>(".journal-callout") ?? null; }
  function ensureWritableTail(canvas: HTMLDivElement) { const last = canvas.lastElementChild; if (!last || !last.matches("details[data-session-id], hr, .journal-callout")) return; canvas.append(line()); }
  function removeTrailingEmptyNeutralLine(canvas: HTMLDivElement) { const last = canvas.lastElementChild; if (last instanceof HTMLParagraphElement && !last.textContent?.trim() && !last.querySelector("img, a, ul, ol")) last.remove(); }
  function removeWritingTailClasses(canvas: HTMLDivElement) { for (const item of Array.from(canvas.querySelectorAll<HTMLElement>(".journal-writing-tail"))) item.classList.remove("journal-writing-tail"); }
  function ensureCalloutControls(canvas: HTMLDivElement) { for (const callout of Array.from(canvas.querySelectorAll<HTMLDivElement>(".journal-callout"))) { if (!callout.dataset.calloutId) callout.dataset.calloutId = crypto.randomUUID(); if (callout.querySelector(":scope > .journal-callout-delete")) continue; const button = document.createElement("button"); button.type = "button"; button.className = "journal-callout-delete"; button.contentEditable = "false"; button.tabIndex = -1; button.setAttribute("aria-label", "Supprimer cet encadré"); button.textContent = "×"; callout.prepend(button); } }
  function ensureSessionHeaders(canvas: HTMLDivElement) {
    for (const section of Array.from(canvas.querySelectorAll<HTMLDetailsElement>("details[data-session-id]"))) {
      const summary = section.querySelector("summary"); if (!summary) continue;
      let datePart = summary.querySelector<HTMLElement>(".journal-session-date"); let toggle = summary.querySelector<HTMLElement>(".journal-session-toggle"); let separator = summary.querySelector<HTMLElement>(".journal-session-separator"); let title = summary.querySelector<HTMLElement>(".journal-session-title");
      if (datePart && toggle && separator && title) { title.contentEditable = section.dataset.locked !== "true" ? "true" : "false"; continue; }
      const label = summary.textContent?.trim() || ""; const parts = sessionParts(label); const date = dateInputFromLabel(label) || todayInput();
      toggle = document.createElement("span"); toggle.className = "journal-session-toggle"; toggle.contentEditable = "false"; toggle.textContent = "▸";
      datePart = document.createElement("span"); datePart.className = "journal-session-date"; datePart.contentEditable = "false"; datePart.dataset.sessionDate = date; datePart.textContent = formatSessionDate(date);
      separator = document.createElement("span"); separator.className = "journal-session-separator"; separator.contentEditable = "false"; separator.textContent = " · ";
      title = document.createElement("span"); title.className = "journal-session-title"; title.contentEditable = section.dataset.locked !== "true" ? "true" : "false"; title.textContent = parts.title || "Nouvelle séance"; summary.replaceChildren(toggle, datePart, separator, title);
    }
  }
  function sessionContentLine(section: HTMLDetailsElement) { return Array.from(section.children).find((element) => element.tagName !== "SUMMARY") as HTMLElement | undefined; }
  function ensureSessionContentLines(canvas: HTMLDivElement) { for (const section of Array.from(canvas.querySelectorAll<HTMLDetailsElement>("details[data-session-id]"))) if (!sessionContentLine(section)) section.querySelector("summary")?.insertAdjacentElement("afterend", line()); }
  function normalizeCanvas(canvas: HTMLDivElement) { ensureSessionHeaders(canvas); ensureSessionContentLines(canvas); ensureCalloutControls(canvas); removeWritingTailClasses(canvas); ensureWritableTail(canvas); }
  function selectionStartsLine(target: HTMLElement) { const selection = window.getSelection(); if (!selection || !selection.rangeCount || !selection.isCollapsed || !target.contains(selection.anchorNode)) return false; const range = document.createRange(); range.selectNodeContents(target); range.setEnd(selection.anchorNode!, selection.anchorOffset); return !range.toString(); }
  function selectionIsInLine(target: HTMLElement) { const selection = window.getSelection(); return Boolean(selection?.rangeCount && selection.isCollapsed && target.contains(selection.anchorNode)); }
  function selectContents(nodes: Node[]) { if (!nodes.length) return; const range = document.createRange(); range.setStartBefore(nodes[0]); range.setEndAfter(nodes[nodes.length - 1]); const selection = window.getSelection(); selection?.removeAllRanges(); selection?.addRange(range); }
  function selectCurrentWritingArea() {
    const canvas = canvasRef.current; const selection = window.getSelection(); if (!canvas || !selection?.rangeCount) return; const element = selectedElement(); const title = element?.closest<HTMLElement>(".journal-session-title");
    if (title) { const range = document.createRange(); range.selectNodeContents(title); selection.removeAllRanges(); selection.addRange(range); return; }
    const callout = currentCallout(); if (callout) { selectContents(Array.from(callout.childNodes).filter((node) => !(node instanceof HTMLElement && node.classList.contains("journal-callout-delete")))); return; }
    const session = currentSession(); if (session) { selectContents(Array.from(session.childNodes).filter((node) => !(node instanceof HTMLElement && node.tagName === "SUMMARY"))); return; }
    const children = Array.from(canvas.children); const current = children.find((child) => child.contains(selection.anchorNode)); const index = current ? children.indexOf(current) : -1; if (index < 0) return; let start = index; let end = index; while (start > 0 && children[start - 1].tagName !== "DETAILS") start--; while (end < children.length - 1 && children[end + 1].tagName !== "DETAILS") end++; selectContents(children.slice(start, end + 1));
  }
  function removeTrulyEmptySessions(canvas: HTMLDivElement) { for (const section of Array.from(canvas.querySelectorAll<HTMLDetailsElement>("details[data-session-id]"))) if (!section.querySelector("summary")) section.remove(); }
  function trimTrailingEmptySessionLines(section: HTMLDetailsElement) { const nodes = Array.from(section.children).filter((item) => item.tagName !== "SUMMARY"); let changed = false; while (nodes.length > 1 && !nodes[nodes.length - 1].textContent?.trim()) { nodes.pop()?.remove(); changed = true; } return changed; }
  function notifyCanvas() { const canvas = canvasRef.current; if (!canvas) return; removeTrulyEmptySessions(canvas); normalizeCanvas(canvas); for (const section of Array.from(canvas.querySelectorAll(".active-session"))) section.classList.remove("active-session"); for (const callout of Array.from(canvas.querySelectorAll(".active-callout"))) callout.classList.remove("active-callout"); updateContent(canvas.innerHTML); }
  function isLocked() { return currentSession()?.dataset.locked === "true"; }
  function command(commandName: "bold" | "italic" | "insertUnorderedList") { if (!ensureSelection() || isLocked()) return; document.execCommand(commandName, false); notifyCanvas(); }
  function historyCommand(commandName: "undo" | "redo") { if (!ensureSelection() || isLocked()) return; document.execCommand(commandName, false); notifyCanvas(); }
  function formatBlock(blockName: "p" | "h2" | "h3" | "h4" | "h5") { if (!ensureSelection() || isLocked()) return; document.execCommand("formatBlock", false, blockName); notifyCanvas(); }
  function applyFont(face: typeof journalFonts[number]["value"]) { if (!ensureSelection() || isLocked()) return; document.execCommand("fontName", false, face); notifyCanvas(); }
  function applyFontSize(size: string) { if (!ensureSelection() || isLocked()) return; document.execCommand("fontSize", false, size); notifyCanvas(); }
  function addLink() { if (!ensureSelection() || isLocked()) return; const href = window.prompt("Adresse du lien"); if (!href) return; document.execCommand("createLink", false, href); notifyCanvas(); }
  function insertHtml(html: string) { if (!ensureSelection() || isLocked()) return; document.execCommand("insertHTML", false, html); notifyCanvas(); }
  function stickyToolbarBottom() {
    const toolbar = document.querySelector<HTMLElement>(".journal-toolbar");
    const shell = toolbar?.closest<HTMLElement>(".player-shell");
    const configuredTabsHeight = Number.parseFloat(shell?.style.getPropertyValue("--player-tabs-height") ?? "");
    const tabsHeight = Number.isFinite(configuredTabsHeight) && configuredTabsHeight > 0
      ? configuredTabsHeight
      : document.querySelector<HTMLElement>(".player-tabs")?.getBoundingClientRect().height || 75;
    return Math.max(0, tabsHeight - 5 + (toolbar?.offsetHeight ?? 0));
  }
  function scrollSessionIntoView(section: HTMLDetailsElement) {
    const targetTop = stickyToolbarBottom() + 8;
    window.scrollTo({ top: Math.max(0, window.scrollY + section.getBoundingClientRect().top - targetTop), behavior: "smooth" });
  }
  function createSession(atDocumentEnd = false, reference?: Element | null) {
    const canvas = canvasRef.current; if (!canvas) return; const nearestSession = atDocumentEnd ? null : currentSession(); const id = crypto.randomUUID(); const section = document.createElement("details"); section.dataset.sessionId = id; section.open = true;
    const summary = document.createElement("summary"); const toggle = document.createElement("span"); toggle.className = "journal-session-toggle"; toggle.contentEditable = "false"; toggle.textContent = "▸"; const date = document.createElement("span"); date.className = "journal-session-date"; date.contentEditable = "false"; date.dataset.sessionDate = todayInput(); date.textContent = formatSessionDate(todayInput()); const separator = document.createElement("span"); separator.className = "journal-session-separator"; separator.contentEditable = "false"; separator.textContent = " · "; const title = document.createElement("span"); title.className = "journal-session-title"; title.textContent = "Nouvelle séance"; summary.append(toggle, date, separator, title); section.append(summary, line());
    if (atDocumentEnd) removeTrailingEmptyNeutralLine(canvas);
    const anchor = atDocumentEnd ? canvas.lastElementChild : nearestSession ?? reference ?? topLevelChild(canvas, selectedElement()); if (anchor && anchor.parentElement === canvas) anchor.insertAdjacentElement("afterend", section); else canvas.append(section); ensureWritableTail(canvas); for (const item of Array.from(canvas.querySelectorAll<HTMLDetailsElement>("details[data-session-id]"))) item.open = item === section; setActiveSessionId(id); setActiveCalloutId(null); notifyCanvas(); requestAnimationFrame(() => { section.open = true; scrollSessionIntoView(section); const first = sessionContentLine(section); if (first) { canvas.focus(); setCaret(first); } });
  }
  function insertCallout() { insertHtml(`<div class="journal-callout" data-callout-id="${crypto.randomUUID()}"><button type="button" contenteditable="false" tabindex="-1" aria-label="Supprimer cet encadré" class="journal-callout-delete">×</button><p><br></p></div>`); }
  function currentEditableBlock() { return selectedElement()?.closest<HTMLElement>("p, h2, h3, h4, h5, blockquote, ul, ol, .journal-callout") ?? null; }
  function changeIndent(delta: number) { if (isLocked()) return; const block = currentEditableBlock(); if (!block || block.matches(".journal-callout")) return; const next = Math.max(0, Math.min(6, Number(block.dataset.indent ?? 0) + delta)); if (next) block.dataset.indent = String(next); else delete block.dataset.indent; notifyCanvas(); }
  function toggleLock() { const section = activeSessionId ? canvasRef.current?.querySelector<HTMLDetailsElement>(`details[data-session-id="${activeSessionId}"]`) : currentSession(); if (!section) return; if (section.dataset.locked === "true") delete section.dataset.locked; else section.dataset.locked = "true"; ensureSessionHeaders(canvasRef.current!); setActiveSessionId(section.dataset.sessionId ?? null); notifyCanvas(); }
  function sortSessions(canvas: HTMLDivElement) { const children = Array.from(canvas.children) as HTMLElement[]; const firstSession = children.findIndex((child) => child.matches("details[data-session-id]")); if (firstSession < 0) return; const intro = children.slice(0, firstSession); const groups: HTMLElement[][] = []; for (let index = firstSession; index < children.length;) { const section = children[index] as HTMLDetailsElement; const group: HTMLElement[] = [section]; index++; while (index < children.length && !children[index].matches("details[data-session-id]")) group.push(children[index++]); groups.push(group); } groups.sort((a, b) => sessionDate(a[0] as HTMLDetailsElement).localeCompare(sessionDate(b[0] as HTMLDetailsElement))); canvas.replaceChildren(...intro, ...groups.flat()); }
  function updateActiveSessionDate(date: string) { const canvas = canvasRef.current; const section = activeSessionId ? canvas?.querySelector<HTMLDetailsElement>(`details[data-session-id="${activeSessionId}"]`) : null; if (!canvas || !section || !date || section.dataset.locked === "true") return; const datePart = section.querySelector<HTMLElement>(".journal-session-date"); if (!datePart) return; datePart.dataset.sessionDate = date; datePart.textContent = formatSessionDate(date); sortSessions(canvas); notifyCanvas(); }
  function requestDeleteActiveSession() { const canvas = canvasRef.current; const section = activeSessionId ? canvas?.querySelector<HTMLDetailsElement>(`details[data-session-id="${activeSessionId}"]`) : currentSession(); if (!section || section.dataset.locked === "true") return; setDeleteCandidate({ id: section.dataset.sessionId ?? "", label: section.querySelector("summary")?.textContent?.trim() || "Séance sans titre" }); }
  function deleteConfirmedSession() { const canvas = canvasRef.current; const section = deleteCandidate ? canvas?.querySelector<HTMLDetailsElement>(`details[data-session-id="${deleteCandidate.id}"]`) : null; if (!canvas || !section) { setDeleteCandidate(null); return; } const next = section.nextElementSibling; section.remove(); ensureWritableTail(canvas); setActiveSessionId(null); setDeleteCandidate(null); canvas.focus(); setCaret(next ?? canvas); notifyCanvas(); }
  function continueBelowContext() { const canvas = canvasRef.current; if (!canvas) return; const callout = currentCallout(); const session = currentSession() ?? (activeSessionId ? canvas.querySelector<HTMLDetailsElement>(`details[data-session-id="${activeSessionId}"]`) : null); if (callout) { const next = line(); callout.insertAdjacentElement("afterend", next); canvas.focus(); setCaret(next); setActiveCalloutId(null); setActiveSessionId(session?.dataset.sessionId ?? null); notifyCanvas(); return; } if (!session) return; trimTrailingEmptySessionLines(session); let next = session.nextElementSibling; if (!(next instanceof HTMLParagraphElement) || next.textContent?.trim()) { next = line(); session.insertAdjacentElement("afterend", next); } canvas.focus(); setCaret(next); setActiveSessionId(null); setActiveCalloutId(null); notifyCanvas(); }
  async function insertImage(file: File) { if (!file.type.startsWith("image/")) { onError("Choisissez un fichier image."); return; } try { const src = demo ? URL.createObjectURL(file) : await uploadQuestJournalImage(page.campaign_id, file); insertHtml(`<img class="journal-inline-image" src="${src}" alt="Image du journal">`); onNotice("Image ajoutée au journal."); } catch (caught) { onError(caught instanceof Error ? caught.message : "Image impossible à ajouter."); } }
  function updateActiveContext() { const section = currentSession(); setActiveSessionId(section?.dataset.sessionId ?? null); setActiveCalloutId(currentCallout()?.dataset.calloutId ?? null); }
  function restoreLocalDraft(draft: JournalDraft) {
    setLocalRecovery(null);
    latestContent.current = draft.content;
    pendingContent.current = draft.content;
    setContent(draft.content);
    setStatus("dirty");
    storeLocalCopy(draft.content);
    if (saveTimer.current) window.clearTimeout(saveTimer.current);
    saveTimer.current = window.setTimeout(() => { saveTimer.current = null; void persistQueuedContent(); }, 0);
  }
  async function loadServerVersion() {
    try {
      const remote = await loadQuestJournalPage(page.campaign_id);
      serverRevision.current = remote.revision ?? 0;
      confirmedContent.current = remote.content;
      latestContent.current = remote.content;
      pendingContent.current = null;
      setContent(remote.content);
      setConflictContent(null);
      setStatus("saved");
      await deleteJournalDraft(page.campaign_id);
      onError(null);
    } catch (caught) { onError(caught instanceof Error ? caught.message : "Impossible de recharger la version serveur."); }
  }
  async function overwriteServerWithLocalCopy() {
    const localCopy = conflictContent;
    if (!localCopy) return;
    try {
      const remote = await loadQuestJournalPage(page.campaign_id);
      serverRevision.current = remote.revision ?? 0;
      confirmedContent.current = remote.content;
      latestContent.current = localCopy;
      pendingContent.current = localCopy;
      setConflictContent(null);
      setContent(localCopy);
      setStatus("dirty");
      void persistQueuedContent();
    } catch (caught) { onError(caught instanceof Error ? caught.message : "Impossible de récupérer la version serveur."); }
  }
  async function restoreRevision(revision: QuestJournalRevision) {
    if (!canRestoreHistory || !window.confirm("Restaurer cette version du Journal ? La version actuelle restera disponible dans l’historique.")) return;
    try {
      const nextRevision = demo ? serverRevision.current + 1 : await restoreQuestJournalRevision(page.campaign_id, revision.id, serverRevision.current);
      serverRevision.current = nextRevision;
      confirmedContent.current = revision.content;
      latestContent.current = revision.content;
      setContent(revision.content);
      storeLocalCopy(revision.content);
      if (!demo) await onChanged();
      setStatus("saved"); setShowHistory(false); onNotice("Version précédente restaurée.");
    } catch (caught) {
      if (caught instanceof QuestJournalVersionConflictError) {
        storeLocalCopy(latestContent.current);
        setConflictContent(latestContent.current);
        setStatus("conflict");
      } else onError(caught instanceof Error ? caught.message : "Restauration impossible.");
    }
  }
  function clickIndex(id: string) { const canvas = canvasRef.current; const section = canvas?.querySelector<HTMLDetailsElement>(`details[data-session-id="${id}"]`); if (!canvas || !section) return; for (const item of Array.from(canvas.querySelectorAll<HTMLDetailsElement>("details[data-session-id]"))) item.open = item === section; setActiveSessionId(id); setActiveCalloutId(null); requestAnimationFrame(() => scrollSessionIntoView(section)); }
  function blockLockedInput(event: FormEvent<HTMLDivElement>) { if (isLocked()) event.preventDefault(); }
  function deleteCallout(event: MouseEvent<HTMLDivElement>) { const target = event.target instanceof Element ? event.target.closest<HTMLButtonElement>(".journal-callout-delete") : null; if (target) { event.preventDefault(); event.stopPropagation(); const callout = target.closest<HTMLElement>(".journal-callout"); if (!callout || callout.closest<HTMLDetailsElement>('details[data-locked="true"]')) return; callout.remove(); setActiveCalloutId(null); notifyCanvas(); return; } const clicked = event.target instanceof Element ? event.target : null; const summary = clicked?.closest("summary"); const toggle = clicked?.closest(".journal-session-toggle, .journal-session-date"); if (summary && !toggle) event.preventDefault(); updateActiveContext(); }
  function keepCanvasWritable(event: KeyboardEvent<HTMLDivElement>) { const title = selectedElement()?.closest(".journal-session-title"); const modifier = event.ctrlKey || event.metaKey; if (modifier && event.key.toLowerCase() === "a") { event.preventDefault(); selectCurrentWritingArea(); return; } if (modifier && event.key.toLowerCase() === "z") { event.preventDefault(); historyCommand(event.shiftKey ? "redo" : "undo"); return; } if (modifier && event.key.toLowerCase() === "y") { event.preventDefault(); historyCommand("redo"); return; } if (event.key === "Enter" && event.ctrlKey) { event.preventDefault(); createSession(true); return; } if (event.key === "Enter" && event.altKey) { event.preventDefault(); continueBelowContext(); return; } if (title) { if (event.key === "Enter") event.preventDefault(); return; } if (isLocked() && ["Backspace", "Delete", "Enter"].includes(event.key)) { event.preventDefault(); return; } const section = currentSession(); const firstLine = section && sessionContentLine(section); if (firstLine && event.key === "Backspace" && selectionStartsLine(firstLine)) { event.preventDefault(); return; } if (firstLine && event.key === "Delete" && selectionIsInLine(firstLine) && !firstLine.textContent?.trim()) { event.preventDefault(); return; } if (event.key === "Enter" && !event.shiftKey) { event.preventDefault(); document.execCommand("insertParagraph"); notifyCanvas(); } }

  return <div className="page-stack quest-writing-page">
    <SectionHeading eyebrow="Registre collaboratif" title="Journal de quête" />
    <p className="section-intro">Votre journal de campagne, pour écrire vos formidables aventures.</p>
    <section className="journal-canvas-layout">
      <aside className={`journal-session-index${compactJournal ? " compact" : ""}`}><header><button type="button" className="journal-navigator-toggle" aria-expanded={compactJournal ? navigatorOpen : true} onClick={() => setNavigatorOpen((open) => !open)}><span>Navigateur</span><small>{sessions.length}</small><ChevronDown className="journal-collapse-icon" size={16} /></button></header><div className="journal-session-index-content" hidden={compactJournal && !navigatorOpen}>{sessions.length > 0 ? sessions.map((session) => { const parts = sessionParts(session.label); return <button key={session.id} className={session.id === activeSessionId ? "active" : ""} onClick={() => clickIndex(session.id)}><time>{parts.date}</time><strong>{parts.title}</strong><ChevronRight size={14} /></button>; }) : <p>Les séances ajoutées apparaîtront ici.</p>}</div><footer hidden={compactJournal && !navigatorOpen}><button type="button" onClick={() => createSession(true)}>+ Séance repliable</button></footer><div className="journal-shortcuts" aria-label="Raccourcis clavier"><span className="journal-shortcuts-title">Raccourcis</span><span><kbd>Alt+Entrée</kbd> sortir du bloc</span><span><kbd>Ctrl+Entrée</kbd> nouvelle séance repliable</span><span><kbd>Ctrl+A</kbd> sélectionner la zone d’écriture</span><span><kbd>Ctrl+Z</kbd> annuler</span><span><kbd>Ctrl+Maj+Z</kbd> ou <kbd>Ctrl+Y</kbd> rétablir</span></div></aside>
      <article className="journal-canvas-panel"><div className={`journal-toolbar${compactJournal ? " compact" : ""}`} role="toolbar" aria-label="Mise en forme" onMouseDown={(event) => { if ((event.target as Element).closest("button")) event.preventDefault(); }}>
        <button type="button" className="journal-toolbar-toggle" aria-expanded={compactJournal ? toolbarOpen : true} onClick={() => { setToolbarOpen((open) => !open); setShowEmojiPicker(false); }}><span>Mise en page</span><ChevronDown className="journal-collapse-icon" size={16} /></button>
        <div className="journal-toolbar-controls" hidden={compactJournal && !toolbarOpen}><button type="button" title="Annuler (Ctrl+Z)" onClick={() => historyCommand("undo")}><Undo2 size={17} /></button><button type="button" title="Rétablir (Ctrl+Shift+Z)" onClick={() => historyCommand("redo")}><Redo2 size={17} /></button><span /><button type="button" title="Gras" onClick={() => command("bold")}><Bold size={17} /></button><button type="button" title="Italique" onClick={() => command("italic")}><Italic size={17} /></button><button type="button" title="Liste" onClick={() => command("insertUnorderedList")}><List size={17} /></button><button type="button" title="Lien" onClick={addLink}><Link size={17} /></button><span />
        <select className="journal-format-picker" aria-label="Niveau de titre" defaultValue="" onChange={(event) => { formatBlock(event.currentTarget.value as "p" | "h2" | "h3" | "h4" | "h5"); event.currentTarget.value = ""; }}><option value="" disabled>Style</option><option value="p">Paragraphe</option><option value="h2">Titre 2</option><option value="h3">Titre 3</option><option value="h4">Titre 4</option><option value="h5">Titre 5</option></select><select className="journal-font-picker" aria-label="Police d’écriture" defaultValue="" onChange={(event) => { applyFont(event.currentTarget.value as typeof journalFonts[number]["value"]); event.currentTarget.value = ""; }}><option value="" disabled>Police</option>{journalFonts.map((font) => <option value={font.value} key={font.value}>{font.label}</option>)}</select><select className="journal-size-picker" aria-label="Taille de police" defaultValue="" onChange={(event) => { applyFontSize(event.currentTarget.value); event.currentTarget.value = ""; }}><option value="" disabled>Taille</option><option value="1">12 px</option><option value="2">14 px</option><option value="3">16 px</option><option value="4">18 px</option><option value="5">22 px</option><option value="6">26 px</option><option value="7">32 px</option></select>
        <button type="button" title="Réduire le retrait" onClick={() => changeIndent(-1)}><IndentDecrease size={17} /></button><button type="button" title="Augmenter le retrait" onClick={() => changeIndent(1)}><IndentIncrease size={17} /></button><button type="button" title="Encadré" onClick={insertCallout}><CircleAlert size={17} /></button><button type="button" title="Insérer une image" onClick={() => uploadInputRef.current?.click()}><ImagePlus size={17} /></button><button type="button" title="Émojis" onClick={() => setShowEmojiPicker((shown) => !shown)}><SmilePlus size={17} /></button><button type="button" title="Préférences de style" onClick={() => setShowPreferences(true)}><Settings2 size={17} /></button><span />
        <button type="button" className="journal-toolbar-label" onClick={() => createSession(true)}>+ Séance repliable</button><label className="journal-session-date-picker" title={activeSession ? "Modifier la date de la séance active" : "Sélectionnez une séance pour modifier sa date"}><span>Date</span><input type="date" disabled={!activeSession || activeSession.locked} value={activeSession?.date ?? ""} onChange={(event) => updateActiveSessionDate(event.currentTarget.value)} /></label><button type="button" disabled={!activeSession && !activeCalloutId} title="Sortir du bloc (Alt+Entrée)" onClick={continueBelowContext}><CornerDownLeft size={16} /></button><button type="button" disabled={!activeSession} className={activeSession ? "active-lock" : ""} title="Verrouiller ou déverrouiller la séance sélectionnée" onClick={toggleLock}>{activeSession?.locked ? <Lock size={16} /> : <Unlock size={16} />}</button><button type="button" disabled={!activeSession || activeSession.locked} className="journal-delete-session" title={activeSession?.locked ? "Impossible de supprimer une séance verrouillée" : "Supprimer la séance sélectionnée"} onClick={requestDeleteActiveSession}><Trash2 size={16} /><span>Supprimer</span></button>{canRestoreHistory && <button type="button" title="Historique des versions" onClick={() => setShowHistory(true)}><History size={16} /></button>}
        {showEmojiPicker && <div className="journal-emoji-picker" role="dialog" aria-label="Choisir un émoji">{emojis.map((emoji) => <button type="button" key={emoji} onClick={() => { insertHtml(emoji); setShowEmojiPicker(false); }}>{emoji}</button>)}</div>}</div>
      </div><input ref={uploadInputRef} className="journal-image-input" type="file" accept="image/*" onChange={(event) => { const file = event.currentTarget.files?.[0]; if (file) void insertImage(file); event.currentTarget.value = ""; }} /><div ref={canvasRef} className="journal-canvas" style={canvasStyle} contentEditable suppressContentEditableWarning role="textbox" aria-label="Journal de quête" data-placeholder="Écrivez vos notes de séance…" onInput={notifyCanvas} onClick={deleteCallout} onKeyUp={updateActiveContext} onKeyDown={keepCanvasWritable} onBeforeInput={blockLockedInput} /><footer><span className={status === "dirty" || status === "conflict" ? "dirty" : ""}>{status === "saving" ? "Enregistrement…" : status === "dirty" ? "Modifications non enregistrées" : status === "conflict" ? "Conflit détecté : copie locale protégée" : "Enregistré"}</span><Save size={15} /></footer></article>
    </section>
    {localRecovery && <div className="modal-backdrop"><section className="modal-card journal-recovery" role="dialog" aria-modal="true" aria-labelledby="journal-recovery-title"><div className="modal-head"><div><p className="eyebrow">Copie de secours locale</p><h3 id="journal-recovery-title">Une version plus récente a été retrouvée</h3></div></div><p>Cette copie a été enregistrée sur cet appareil le {new Date(localRecovery.savedAt).toLocaleString("fr-CH", { dateStyle: "medium", timeStyle: "short" })}. Vous pouvez la restaurer sans perdre la version actuellement sur le serveur.</p><div className="modal-actions"><button type="button" className="button secondary" onClick={() => { void deleteJournalDraft(page.campaign_id); setLocalRecovery(null); }}>Conserver le serveur</button><button type="button" className="button primary" onClick={() => restoreLocalDraft(localRecovery)}>Restaurer ma copie locale</button></div></section></div>}
    {conflictContent !== null && <div className="modal-backdrop"><section className="modal-card journal-recovery" role="dialog" aria-modal="true" aria-labelledby="journal-conflict-title"><div className="modal-head"><div><p className="eyebrow">Sauvegarde protégée</p><h3 id="journal-conflict-title">Le Journal a été modifié ailleurs</h3></div></div><p>Votre texte n’a pas été écrasé : il reste enregistré sur cet appareil. Choisissez explicitement la version à conserver.</p><div className="modal-actions"><button type="button" className="button secondary" onClick={() => void loadServerVersion()}>Charger la version serveur</button><button type="button" className="button primary" onClick={() => void overwriteServerWithLocalCopy()}>Remplacer par ma copie</button></div></section></div>}
    {deleteCandidate && <div className="modal-backdrop" role="presentation"><section className="modal-card journal-delete-confirm" role="dialog" aria-modal="true" aria-labelledby="journal-delete-title"><div className="modal-head"><div><p className="eyebrow">Journal de quête</p><h3 id="journal-delete-title">Supprimer cette note ?</h3></div></div><p>Voulez-vous vraiment supprimer la note nommée « {sessionParts(deleteCandidate.label).title || deleteCandidate.label} » ?</p><div className="modal-actions"><button type="button" className="button secondary" onClick={() => setDeleteCandidate(null)}>Non</button><button type="button" className="button danger-solid" onClick={deleteConfirmedSession}>Oui, supprimer</button></div></section></div>}
    {showHistory && <div className="modal-backdrop"><section className="modal-card journal-history" role="dialog" aria-modal="true" aria-labelledby="journal-history-title"><div className="modal-head"><div><p className="eyebrow">Journal partagé</p><h3 id="journal-history-title">Historique du Journal</h3></div><button className="icon-button" type="button" onClick={() => setShowHistory(false)}><X /></button></div><p>Restaurer une version crée d’abord un instantané de l’état actuel.</p><div className="journal-history-list">{revisions.length > 0 ? revisions.map((revision) => <button type="button" key={revision.id} onClick={() => void restoreRevision(revision)}><span>{new Date(revision.created_at).toLocaleString("fr-CH", { dateStyle: "medium", timeStyle: "short" })}</span><small>{sessionsFromContent(revision.content).length} séance{sessionsFromContent(revision.content).length > 1 ? "s" : ""}</small><span>Restaurer</span></button>) : <p>Aucune version antérieure n’est encore disponible.</p>}</div><div className="modal-actions"><button type="button" className="button secondary" onClick={() => setShowHistory(false)}>Fermer</button></div></section></div>}
    {showPreferences && <div className="modal-backdrop"><section className="modal-card journal-preferences" role="dialog" aria-modal="true" aria-labelledby="journal-preferences-title"><div className="modal-head"><div><p className="eyebrow">Journal de quête</p><h3 id="journal-preferences-title">Préférences de style</h3></div><button className="icon-button" type="button" onClick={() => setShowPreferences(false)}><X /></button></div><div className="form-grid"><label>Police par défaut<select value={preferences.font} onChange={(event) => setPreferences({ ...preferences, font: event.currentTarget.value })}>{journalFonts.map((font) => <option key={font.value} value={font.value}>{font.label}</option>)}</select></label><label>Taille par défaut<input type="number" min="12" max="24" value={preferences.size} onChange={(event) => setPreferences({ ...preferences, size: Number(event.currentTarget.value) || defaultPreferences.size })} /></label><label>Police des titres<select value={preferences.headingFont} onChange={(event) => setPreferences({ ...preferences, headingFont: event.currentTarget.value })}>{journalFonts.map((font) => <option key={font.value} value={font.value}>{font.label}</option>)}</select></label><label>Interligne<input type="number" min="1.2" max="2.4" step=".05" value={preferences.lineHeight} onChange={(event) => setPreferences({ ...preferences, lineHeight: Number(event.currentTarget.value) || defaultPreferences.lineHeight })} /></label><label>Retrait horizontal<input type="number" min="10" max="80" value={preferences.indent} onChange={(event) => setPreferences({ ...preferences, indent: Number(event.currentTarget.value) || defaultPreferences.indent })} /></label><label>Titre 2<input type="number" min="16" max="40" value={preferences.h2} onChange={(event) => setPreferences({ ...preferences, h2: Number(event.currentTarget.value) || defaultPreferences.h2 })} /></label><label>Titre 3<input type="number" min="14" max="34" value={preferences.h3} onChange={(event) => setPreferences({ ...preferences, h3: Number(event.currentTarget.value) || defaultPreferences.h3 })} /></label><label>Titre 4<input type="number" min="13" max="30" value={preferences.h4} onChange={(event) => setPreferences({ ...preferences, h4: Number(event.currentTarget.value) || defaultPreferences.h4 })} /></label><label>Titre 5<input type="number" min="12" max="26" value={preferences.h5} onChange={(event) => setPreferences({ ...preferences, h5: Number(event.currentTarget.value) || defaultPreferences.h5 })} /></label></div><div className="modal-actions"><button type="button" className="button secondary" onClick={() => setPreferences(defaultPreferences)}>Réinitialiser</button><button type="button" className="button primary" onClick={() => setShowPreferences(false)}>Fermer</button></div></section></div>}
  </div>;
}
