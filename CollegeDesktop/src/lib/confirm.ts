/** Destructive confirm helper — returns true when the user proceeds. */
export function confirmDelete(label: string): boolean {
  return window.confirm(`Delete ${label}?\n\nThis can’t be undone.`);
}

/** Confirm cascade delete of a non-empty folder. */
export function confirmFolderCascadeDelete(folderTitle: string, childCount: number): boolean {
  const label = folderTitle || "folder";
  const noun = childCount === 1 ? "item" : "items";
  return window.confirm(
    `Delete folder and ${childCount} ${noun}?\n\n“${label}” and everything inside will be permanently removed.`,
  );
}

export function confirmDanger(message: string): boolean {
  return window.confirm(message);
}
