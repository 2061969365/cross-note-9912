import { openDb, migrate } from "./db.js";
const db = openDb();
migrate(db);
console.log("migrated");
db.close();
