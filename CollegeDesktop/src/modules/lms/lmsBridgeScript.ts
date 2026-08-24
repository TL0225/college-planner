export type LmsExtractedItem = {
  kind: string;
  title: string;
  dueAt?: string | null;
  courseCode?: string | null;
  notes?: string | null;
  lmsItemId?: string | null;
};

export type LmsExtractResult = {
  pageType: string;
  items: LmsExtractedItem[];
};
