import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
import { useModalFocus } from "../src/lib/useModalFocus";
import { ModalFrame } from "../src/components/ModalFrame";

it("une récupération de brouillon exige un choix explicite et reste ouverte avec Échap", async () => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  const container = document.createElement("div");
  document.body.append(container);
  const root = createRoot(container);
  try {
    await act(async () => root.render(<ModalFrame label="Récupérer le brouillon"><section><button>Conserver</button><button>Restaurer</button></section></ModalFrame>));
    const dialog = container.querySelector('[role="dialog"]')!;
    expect(dialog.getAttribute("aria-modal")).toBe("true");
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    expect(dialog.isConnected).toBe(true);
    expect(dialog.contains(document.activeElement)).toBe(true);
  } finally { act(() => root.unmount()); container.remove(); }
});

function Modal({ name, onClose }: { name: string; onClose: () => void }) {
  const ref = useModalFocus(true, onClose);
  return <section ref={(node) => { ref.current = node; }} tabIndex={-1} aria-label={name}>
    <button>{name} début</button><button>{name} fin</button>
  </section>;
}

it("la touche Tab reste dans la fenêtre dans les deux sens", async () => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  const container = document.createElement("div");
  document.body.append(container);
  const root = createRoot(container);
  try {
    await act(async () => root.render(<Modal name="Test" onClose={() => undefined} />));
    const [first, last] = container.querySelectorAll("button");
    expect(document.activeElement).toBe(first);
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Tab", shiftKey: true, bubbles: true, cancelable: true }));
    expect(document.activeElement).toBe(last);
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Tab", bubbles: true, cancelable: true }));
    expect(document.activeElement).toBe(first);
  } finally { act(() => root.unmount()); container.remove(); }
});

it("seule la fenêtre au premier plan reçoit Échap quand deux fenêtres sont ouvertes", async () => {
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  const container = document.createElement("div");
  document.body.append(container);
  const root = createRoot(container);
  const closeFirst = vi.fn();
  const closeSecond = vi.fn();
  try {
    await act(async () => root.render(<><Modal name="Première" onClose={closeFirst} /><Modal name="Seconde" onClose={closeSecond} /></>));
    expect(container.querySelector('[aria-label="Seconde"]')?.contains(document.activeElement)).toBe(true);
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    expect(closeFirst).not.toHaveBeenCalled();
    expect(closeSecond).toHaveBeenCalledOnce();
    await act(async () => root.render(<Modal name="Première" onClose={closeFirst} />));
    expect(document.body.style.overflow).toBe("hidden");
  } finally { act(() => root.unmount()); container.remove(); }
  expect(document.body.style.overflow).not.toBe("hidden");
});
