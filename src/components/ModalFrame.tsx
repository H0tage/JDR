import { cloneElement, type HTMLAttributes, type ReactElement, type Ref } from "react";
import { useModalFocus } from "../lib/useModalFocus";

type ContentProps = HTMLAttributes<HTMLElement> & { ref?: Ref<HTMLElement> };

/** Shared modal behavior; the existing form/section keeps its layout and theme. */
export function ModalFrame({ children, label, onClose, dismissOnBackdrop = false }: {
  children: ReactElement<ContentProps>;
  label: string;
  onClose?: () => void;
  dismissOnBackdrop?: boolean;
}) {
  // Recovery/conflict dialogs deliberately require an explicit choice.
  const ref = useModalFocus(true, () => onClose?.());
  return <div className="modal-backdrop" role="presentation" onMouseDown={(event) => {
    if (dismissOnBackdrop && event.target === event.currentTarget) onClose?.();
  }}>{cloneElement(children, {
    ref: (node: HTMLElement | null) => { ref.current = node; },
    role: "dialog", "aria-modal": true, tabIndex: -1,
    "aria-label": children.props["aria-labelledby"] ? undefined : label,
  })}</div>;
}
