import { useEffect, useRef } from "react";

const modalStack: HTMLElement[] = [];
let originalOverflow = "";

/** Keep keyboard navigation inside an open modal and restore its trigger. */
export function useModalFocus(open: boolean, onClose: () => void) {
  const ref = useRef<HTMLElement | null>(null);
  const close = useRef(onClose);
  close.current = onClose;
  useEffect(() => {
    if (!open || !ref.current) return;
    const modal = ref.current;
    const previous = document.activeElement as HTMLElement | null;
    if (!modalStack.length) originalOverflow = document.body.style.overflow;
    modalStack.push(modal);
    document.body.style.overflow = "hidden";
    const focusable = () => Array.from(modal.querySelectorAll<HTMLElement>(
      'button:not(:disabled), input:not(:disabled):not([type="hidden"]), select:not(:disabled), textarea:not(:disabled), a[href], [tabindex="0"]',
    )).filter((element) => element.tabIndex >= 0 && !element.closest('[hidden], [inert]') && getComputedStyle(element).display !== "none" && getComputedStyle(element).visibility !== "hidden");
    (focusable()[0] ?? modal).focus();
    const keydown = (event: KeyboardEvent) => {
      if (modalStack.at(-1) !== modal) return;
      if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); close.current(); }
      if (event.key !== "Tab") return;
      const elements = focusable();
      const first = elements[0] ?? modal;
      const last = elements.at(-1) ?? modal;
      if (!modal.contains(document.activeElement) || (!event.shiftKey && document.activeElement === last)) {
        event.preventDefault(); first.focus();
      } else if (event.shiftKey && document.activeElement === first) {
        event.preventDefault(); last.focus();
      }
    };
    const focusin = (event: FocusEvent) => {
      if (modalStack.at(-1) !== modal) return;
      if (!modal.contains(event.target as Node)) (focusable()[0] ?? modal).focus();
    };
    document.addEventListener("keydown", keydown, true);
    document.addEventListener("focusin", focusin);
    return () => {
      document.removeEventListener("keydown", keydown, true);
      document.removeEventListener("focusin", focusin);
      const index = modalStack.indexOf(modal);
      if (index !== -1) modalStack.splice(index, 1);
      if (!modalStack.length) document.body.style.overflow = originalOverflow;
      if (previous?.isConnected) previous.focus();
    };
  }, [open]);
  return ref;
}
