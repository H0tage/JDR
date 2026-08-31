export type JournalDraft = {
  campaignId: string;
  content: string;
  revision: number;
  savedAt: number;
};

const databaseName = "blood-lords-journal-drafts";
const storeName = "drafts";
const fallbackPrefix = "blood-lords-journal-draft:";

function fallbackKey(campaignId: string) { return `${fallbackPrefix}${campaignId}`; }

function canUseIndexedDb() { return typeof window !== "undefined" && "indexedDB" in window; }

function openDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = window.indexedDB.open(databaseName, 1);
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains(storeName)) request.result.createObjectStore(storeName, { keyPath: "campaignId" });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function fallbackRead(campaignId: string): JournalDraft | null {
  try {
    const raw = window.localStorage.getItem(fallbackKey(campaignId));
    return raw ? JSON.parse(raw) as JournalDraft : null;
  } catch { return null; }
}

function fallbackWrite(draft: JournalDraft) {
  try { window.localStorage.setItem(fallbackKey(draft.campaignId), JSON.stringify(draft)); } catch { /* Navigation privée ou quota : l’éditeur continue sans cache local. */ }
}

export async function readJournalDraft(campaignId: string): Promise<JournalDraft | null> {
  if (!canUseIndexedDb()) return fallbackRead(campaignId);
  try {
    const database = await openDatabase();
    return await new Promise<JournalDraft | null>((resolve, reject) => {
      const request = database.transaction(storeName, "readonly").objectStore(storeName).get(campaignId);
      request.onsuccess = () => resolve((request.result as JournalDraft | undefined) ?? null);
      request.onerror = () => reject(request.error);
    });
  } catch { return fallbackRead(campaignId); }
}

export async function writeJournalDraft(draft: JournalDraft): Promise<void> {
  fallbackWrite(draft);
  if (!canUseIndexedDb()) return;
  try {
    const database = await openDatabase();
    await new Promise<void>((resolve, reject) => {
      const request = database.transaction(storeName, "readwrite").objectStore(storeName).put(draft);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });
  } catch { /* Le secours localStorage reste disponible. */ }
}

export async function deleteJournalDraft(campaignId: string): Promise<void> {
  try { window.localStorage.removeItem(fallbackKey(campaignId)); } catch { /* sans effet */ }
  if (!canUseIndexedDb()) return;
  try {
    const database = await openDatabase();
    await new Promise<void>((resolve, reject) => {
      const request = database.transaction(storeName, "readwrite").objectStore(storeName).delete(campaignId);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });
  } catch { /* sans effet */ }
}
