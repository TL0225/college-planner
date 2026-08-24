type ToastKind = "info" | "success" | "error";

export type ToastPayload = {
  id: number;
  message: string;
  kind: ToastKind;
};

const EVENT = "college:toast";

let seq = 0;

export function showToast(message: string, kind: ToastKind = "info") {
  const payload: ToastPayload = { id: ++seq, message, kind };
  window.dispatchEvent(new CustomEvent(EVENT, { detail: payload }));
}

export function subscribeToasts(handler: (toast: ToastPayload) => void): () => void {
  const onToast = (ev: Event) => {
    const detail = (ev as CustomEvent<ToastPayload>).detail;
    if (detail) handler(detail);
  };
  window.addEventListener(EVENT, onToast);
  return () => window.removeEventListener(EVENT, onToast);
}
