export type Note = {
  id: string;
  folder_id: string | null;
  title: string;
  content: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  version: number;
  device_id: string;
};

export type Folder = {
  id: string;
  name: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  version: number;
  device_id: string;
};

export type SyncOperation = "CREATE" | "UPDATE" | "DELETE";
export type EntityType = "note" | "folder";
