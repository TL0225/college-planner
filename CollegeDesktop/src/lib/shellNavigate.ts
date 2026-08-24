export type ShellNavigateDetail = {
  module: string;
  page?: string;
};

export function shellNavigate(module: string, page?: string) {
  window.dispatchEvent(
    new CustomEvent("college:navigate", {
      detail: { module, page } satisfies ShellNavigateDetail,
    }),
  );
}
