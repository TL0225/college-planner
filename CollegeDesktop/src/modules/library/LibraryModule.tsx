import { DocumentsModule } from "@/modules/documents/DocumentsModule";
import { ProfileModule } from "@/modules/profile/ProfileModule";
import { libraryPageToLegacy } from "@/lib/shell/defaults";

export function LibraryModule({ page }: { page: string }) {
  const legacy = libraryPageToLegacy(page);

  if (legacy.profile) {
    return <ProfileModule page={legacy.profile} />;
  }

  return <DocumentsModule page={legacy.documents ?? page} />;
}
