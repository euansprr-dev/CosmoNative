// CosmoOS/Data/Database/CosmoDatabase.swift
// GRDB-based SQLite database manager
// CRITICAL: Uses SAME database file as web app for seamless parallel development

import GRDB
import Foundation

// MARK: - String Helper for Table Name Singularization

extension String {
    /// Convert plural table name to singular entity type
    /// e.g., "ideas" -> "idea", "journal_entries" -> "journal_entry"
    func singularized() -> String {
        // Handle special cases first
        let specialCases: [String: String] = [
            "ideas": "idea",
            "tasks": "task",
            "projects": "project",
            "content": "content",
            "research": "research",
            "connections": "connection",
            "journal_entries": "journal_entry",
            "calendar_events": "calendar_event",
            "schedule_blocks": "schedule_block",
            "uncommitted_items": "uncommitted_item",
            "canvas_blocks": "canvas_block",
            "semantic_chunks": "semantic_chunk"
        ]

        if let singular = specialCases[self] {
            return singular
        }

        // Generic singularization: remove trailing 's' or 'es'
        if self.hasSuffix("ies") {
            return String(self.dropLast(3)) + "y"
        } else if self.hasSuffix("es") {
            return String(self.dropLast(2))
        } else if self.hasSuffix("s") {
            return String(self.dropLast())
        }

        return self
    }
}

@MainActor
class CosmoDatabase: ObservableObject {
    static let shared = CosmoDatabase()

    var dbQueue: DatabaseQueue!
    @Published var isReady = false
    @Published var error: String? = nil

    /// The Sendable actor core for use by FoundationModels tools
    private(set) var actorCore: DatabaseActorCore?

    private init() {
        setupDatabase()
    }

    private func setupDatabase() {
        do {
            let dbPath = Self.databasePath

            // Ensure directory exists
            let directory = dbPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            // Create/open database.
            // busyMode: the file is shared with CosmoVoiceDaemon / the web app —
            // without a busy timeout, cross-process write contention surfaces as
            // instant SQLITE_BUSY errors that the many `try?` call sites swallow
            // as silent save failures.
            var config = Configuration()
            config.busyMode = .timeout(5.0)
            dbQueue = try DatabaseQueue(path: dbPath.path, configuration: config)

            // Daily safety backup. When a migration is about to run, take it
            // synchronously BEFORE migrating so a bad migration stays
            // recoverable. On every other launch, defer the copy off the
            // launch path — the file is 250MB+ and the synchronous copy was
            // costing 1–2s of cold open once per day.
            let hasPendingMigrations = !((try? dbQueue.read { try migrator.hasCompletedMigrations($0) }) ?? false)
            if hasPendingMigrations {
                Self.performDailyBackupIfNeeded(dbPath: dbPath)
            }

            // Configure PRAGMA settings - ALL must be outside transactions
            // These settings modify the database behavior and can't be changed mid-transaction
            try dbQueue.inDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode = WAL")
                try db.execute(sql: "PRAGMA foreign_keys = ON")
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
                try db.execute(sql: "PRAGMA temp_store = MEMORY")
                try db.execute(sql: "PRAGMA mmap_size = 30000000000")
            }

            // Run migrations (this will create tables)
            try migrator.migrate(dbQueue)

            // Auto-track local canvas_blocks writes for cloud sync. Registered
            // AFTER migrations so schema maintenance never enqueues pushes.
            dbQueue.add(transactionObserver: CanvasBlockSyncObserver.shared, extent: .databaseLifetime)
            dbQueue.add(transactionObserver: CanvasDrawingSyncObserver.shared, extent: .databaseLifetime)

            // Initialize the Sendable actor core for FoundationModels tools
            let core = DatabaseActorCore(queue: dbQueue)
            self.actorCore = core
            DatabaseActorCore.shared = core

            isReady = true
            print("✅ Database ready at: \(dbPath.path)")

            // Deferred daily backup (no migration ran, so pre/post state is
            // identical) + periodic file maintenance. Both run well after the
            // interactive startup settles; the online backup API is safe
            // against the live WAL database.
            if !hasPendingMigrations {
                Task.detached(priority: .background) {
                    try? await Task.sleep(for: .seconds(15))
                    Self.performDailyBackupIfNeeded(dbPath: dbPath)
                    await Self.performMaintenanceIfNeeded()
                }
            }

        } catch {
            self.error = "Database initialization failed: \(error.localizedDescription)"
            print("❌ Database error: \(error)")
        }
    }

    // MARK: - Backups

    /// Copy the database into Cosmo/backups/ at most once per day, keeping the
    /// last 3 copies. Runs before migrations when one is pending (so a bad
    /// migration is recoverable); otherwise deferred off the launch path.
    /// Uses SQLite's online backup (via GRDB) so a hot WAL doesn't corrupt the copy.
    private nonisolated static func performDailyBackupIfNeeded(dbPath: URL) {
        guard !isRunningTests, FileManager.default.fileExists(atPath: dbPath.path) else { return }

        let backupDir = dbPath.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("backups")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let stamp = formatter.string(from: Date())
        let backupURL = backupDir.appendingPathComponent("Databases-\(stamp).db")

        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }

        do {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            let source = try DatabaseQueue(path: dbPath.path)
            let destination = try DatabaseQueue(path: backupURL.path)
            try source.backup(to: destination)
            print("💾 Database backed up to \(backupURL.lastPathComponent)")

            // Prune to the 3 newest backups
            let backups = (try? FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil))?
                .filter { $0.lastPathComponent.hasPrefix("Databases-") && $0.pathExtension == "db" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
            for stale in backups.dropFirst(3) {
                try? FileManager.default.removeItem(at: stale)
            }
        } catch {
            print("⚠️ Database backup failed (continuing): \(error)")
        }
    }

    // MARK: - Maintenance

    private nonisolated static let maintenanceStampKey = "com.cosmo.lastDbMaintenance"
    private nonisolated static let maintenanceInterval: TimeInterval = 7 * 24 * 3600

    /// Weekly file maintenance: FTS index optimize + VACUUM. The July 2026
    /// audit found ~38% of the database file was free pages (sync_queue payload
    /// churn leaves them behind); VACUUM returns them to the filesystem, which
    /// also shrinks every future daily backup. Runs only on the deferred
    /// background path — never during interactive startup — and waits an extra
    /// beat so launch-time sync traffic isn't contending with the write lock.
    private nonisolated static func performMaintenanceIfNeeded() async {
        guard !ProcessInfo.processInfo.isRunningTests else { return }
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: maintenanceStampKey) as? Date,
           Date().timeIntervalSince(last) < maintenanceInterval {
            return
        }

        // Let launch-time sync pushes/pulls drain before taking long locks.
        try? await Task.sleep(for: .seconds(45))

        let queue = await MainActor.run { shared.isReady ? shared.dbQueue : nil }
        guard let queue else { return }

        let start = Date()
        do {
            // Best-effort FTS housekeeping; a missing FTS table is non-fatal.
            queue.inDatabase { db in
                try? db.execute(sql: "INSERT INTO atoms_fts(atoms_fts) VALUES('optimize')")
                try? db.execute(sql: "INSERT INTO context_chunks_fts(context_chunks_fts) VALUES('optimize')")
            }
            // VACUUM cannot run inside a transaction; inDatabase executes it
            // bare. GRDB serializes it against this process's other writes and
            // the cross-process busy timeout covers the daemon/web app.
            try queue.inDatabase { db in
                try db.execute(sql: "VACUUM")
            }
            defaults.set(Date(), forKey: maintenanceStampKey)
            let seconds = Date().timeIntervalSince(start)
            print("🧹 Database maintenance (FTS optimize + VACUUM) done in \(String(format: "%.1f", seconds))s")
        } catch {
            print("⚠️ Database maintenance failed (continuing): \(error)")
        }
    }

    // MARK: - Database Path
    static var databasePath: URL {
        if isRunningTests {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("CosmoOSTests-\(ProcessInfo.processInfo.processIdentifier)")
                .appendingPathComponent("databases")
                .appendingPathComponent("Databases.db")
        }

        // CRITICAL: Same path as web app's SQLite for seamless migration
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        // Web app stores at: Cosmo/databases/Databases.db
        return appSupport
            .appendingPathComponent("Cosmo")
            .appendingPathComponent("databases")
            .appendingPathComponent("Databases.db")
    }

    private nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.isRunningTests
    }

    // MARK: - Database Migrator
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // Create schema (use inline for reliability)
        // NOTE: Using static method to avoid @MainActor deadlock in migration closures
        migrator.registerMigration("create_schema") { db in
            print("🔨 Creating database schema...")
            try Self.createMinimalSchema(db)
            print("✅ Database schema created")
        }

        // Add focus_blocks column to entity tables for document-scoped floating blocks
        // Safe migration: ignores errors if columns already exist
        migrator.registerMigration("add_focus_blocks") { db in
            print("🔨 Adding focus_blocks columns...")

            // Safe add - ignore if column already exists
            for table in ["ideas", "content", "research"] {
                do {
                    try db.execute(sql: "ALTER TABLE \(table) ADD COLUMN focus_blocks TEXT")
                    print("  ✅ Added focus_blocks to \(table)")
                } catch {
                    // Column likely already exists, continue
                    print("  ⚠️ Column focus_blocks may already exist in \(table): \(error.localizedDescription)")
                }
            }

            print("✅ focus_blocks migration complete")
        }

        // Add sync tracking columns to all entity tables
        // These columns enable local-first sync with conflict resolution
        migrator.registerMigration("add_sync_columns") { db in
            print("🔨 Adding sync tracking columns...")

            let tables = ["ideas", "content", "tasks", "projects", "research",
                          "connections", "calendar_events", "journal_entries", "canvas_blocks"]

            for table in tables {
                // Add _local_version (default 1 for existing rows)
                do {
                    try db.execute(sql: "ALTER TABLE \(table) ADD COLUMN _local_version INTEGER DEFAULT 1")
                    print("  ✅ Added _local_version to \(table)")
                } catch {
                    print("  ⚠️ _local_version may already exist in \(table)")
                }

                // Add _server_version (default 0 for unsynced rows)
                do {
                    try db.execute(sql: "ALTER TABLE \(table) ADD COLUMN _server_version INTEGER DEFAULT 0")
                    print("  ✅ Added _server_version to \(table)")
                } catch {
                    print("  ⚠️ _server_version may already exist in \(table)")
                }

                // Add _sync_version (default 0)
                do {
                    try db.execute(sql: "ALTER TABLE \(table) ADD COLUMN _sync_version INTEGER DEFAULT 0")
                    print("  ✅ Added _sync_version to \(table)")
                } catch {
                    print("  ⚠️ _sync_version may already exist in \(table)")
                }
            }

            // Also add _local_pending to canvas_blocks if missing
            do {
                try db.execute(sql: "ALTER TABLE canvas_blocks ADD COLUMN _local_pending INTEGER DEFAULT 0")
                print("  ✅ Added _local_pending to canvas_blocks")
            } catch {
                print("  ⚠️ _local_pending may already exist in canvas_blocks")
            }

            // Also add _local_pending to atoms if missing
            do {
                try db.execute(sql: "ALTER TABLE atoms ADD COLUMN _local_pending INTEGER DEFAULT 0")
                print("  ✅ Added _local_pending to atoms")
            } catch {
                print("  ⚠️ _local_pending may already exist in atoms")
            }

            print("✅ Sync columns migration complete")
        }

        // Add color column to tasks table for calendar item customization
        migrator.registerMigration("add_tasks_color") { db in
            print("🔨 Adding color column to tasks...")
            do {
                try db.execute(sql: "ALTER TABLE tasks ADD COLUMN color TEXT")
                print("  ✅ Added color to tasks")
            } catch {
                print("  ⚠️ color column may already exist in tasks: \(error.localizedDescription)")
            }
            print("✅ tasks.color migration complete")
        }

        // Create uncommitted_items table for capturing raw cognition before commitment
        migrator.registerMigration("create_uncommitted_items") { db in
            print("🔨 Creating uncommitted_items table...")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS uncommitted_items (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    uuid TEXT NOT NULL UNIQUE,
                    user_id TEXT,

                    -- Core content
                    raw_text TEXT NOT NULL,
                    capture_method TEXT NOT NULL DEFAULT 'keyboard',

                    -- Inference
                    inferred_project TEXT,
                    inferred_project_confidence REAL,
                    inferred_type TEXT,

                    -- Assignment
                    assignment_status TEXT NOT NULL DEFAULT 'unassigned',
                    project_id INTEGER,
                    project_uuid TEXT,

                    -- Promotion
                    promoted_to TEXT,
                    promoted_entity_id INTEGER,
                    promoted_entity_uuid TEXT,

                    -- Lifecycle
                    is_archived INTEGER DEFAULT 0,
                    expires_at TEXT,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    synced_at TEXT,
                    is_deleted INTEGER DEFAULT 0,

                    -- Sync tracking
                    _local_version INTEGER DEFAULT 1,
                    _server_version INTEGER DEFAULT 0,
                    _sync_version INTEGER DEFAULT 0,

                    FOREIGN KEY (project_id) REFERENCES projects(id)
                );

                CREATE INDEX IF NOT EXISTS idx_uncommitted_assignment
                    ON uncommitted_items(assignment_status, project_id);
                CREATE INDEX IF NOT EXISTS idx_uncommitted_archived
                    ON uncommitted_items(is_archived);
                CREATE INDEX IF NOT EXISTS idx_uncommitted_created
                    ON uncommitted_items(created_at DESC);
                CREATE INDEX IF NOT EXISTS idx_uncommitted_promoted
                    ON uncommitted_items(promoted_to, promoted_entity_id);
            """)
            print("✅ uncommitted_items table created successfully")
        }

        // Create FTS5 virtual table for BM25 keyword search (hybrid search foundation)
        // FTS5 provides fast, ranked full-text search with porter stemming
        migrator.registerMigration("create_semantic_fts") { db in
            print("🔨 Creating FTS5 full-text search index...")

            // Create FTS5 virtual table with porter stemmer for English
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS semantic_fts USING fts5(
                    entity_type,
                    entity_id UNINDEXED,
                    title,
                    content,
                    tags,
                    tokenize='porter unicode61 remove_diacritics 1'
                );
            """)

            // Populate FTS index from existing entities
            print("  📝 Indexing ideas...")
            try db.execute(sql: """
                INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                SELECT 'idea', id, COALESCE(title, ''), COALESCE(content, ''), COALESCE(tags, '')
                FROM ideas WHERE is_deleted = 0;
            """)

            print("  📝 Indexing content...")
            try db.execute(sql: """
                INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                SELECT 'content', id, COALESCE(title, ''), COALESCE(body, ''), COALESCE(tags, '')
                FROM content WHERE is_deleted = 0;
            """)

            print("  📝 Indexing research...")
            try db.execute(sql: """
                INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                SELECT 'research', id, COALESCE(title, ''), COALESCE(summary, ''), COALESCE(tags, '')
                FROM research WHERE is_deleted = 0;
            """)

            print("  📝 Indexing connections...")
            try db.execute(sql: """
                INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                SELECT 'connection', id, COALESCE(title, ''),
                       COALESCE(idea, '') || ' ' || COALESCE(goal, '') || ' ' || COALESCE(problems, ''),
                       ''
                FROM connections WHERE is_deleted = 0;
            """)

            print("  📝 Indexing tasks...")
            try db.execute(sql: """
                INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                SELECT 'task', id, COALESCE(title, ''), COALESCE(description, ''), ''
                FROM tasks WHERE is_deleted = 0;
            """)

            print("✅ FTS5 search index created successfully")
        }

        // Create triggers to keep FTS index in sync with entity tables
        migrator.registerMigration("create_fts_triggers") { db in
            print("🔨 Creating FTS sync triggers...")

            // Ideas triggers
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS ideas_fts_insert AFTER INSERT ON ideas
                WHEN NEW.is_deleted = 0
                BEGIN
                    INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                    VALUES ('idea', NEW.id, COALESCE(NEW.title, ''), COALESCE(NEW.content, ''), COALESCE(NEW.tags, ''));
                END;

                CREATE TRIGGER IF NOT EXISTS ideas_fts_update AFTER UPDATE ON ideas
                WHEN NEW.is_deleted = 0
                BEGIN
                    DELETE FROM semantic_fts WHERE entity_type = 'idea' AND entity_id = OLD.id;
                    INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                    VALUES ('idea', NEW.id, COALESCE(NEW.title, ''), COALESCE(NEW.content, ''), COALESCE(NEW.tags, ''));
                END;

                CREATE TRIGGER IF NOT EXISTS ideas_fts_delete AFTER UPDATE ON ideas
                WHEN NEW.is_deleted = 1 AND OLD.is_deleted = 0
                BEGIN
                    DELETE FROM semantic_fts WHERE entity_type = 'idea' AND entity_id = OLD.id;
                END;
            """)

            // Content triggers
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS content_fts_insert AFTER INSERT ON content
                WHEN NEW.is_deleted = 0
                BEGIN
                    INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                    VALUES ('content', NEW.id, COALESCE(NEW.title, ''), COALESCE(NEW.body, ''), COALESCE(NEW.tags, ''));
                END;

                CREATE TRIGGER IF NOT EXISTS content_fts_update AFTER UPDATE ON content
                WHEN NEW.is_deleted = 0
                BEGIN
                    DELETE FROM semantic_fts WHERE entity_type = 'content' AND entity_id = OLD.id;
                    INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                    VALUES ('content', NEW.id, COALESCE(NEW.title, ''), COALESCE(NEW.body, ''), COALESCE(NEW.tags, ''));
                END;

                CREATE TRIGGER IF NOT EXISTS content_fts_delete AFTER UPDATE ON content
                WHEN NEW.is_deleted = 1 AND OLD.is_deleted = 0
                BEGIN
                    DELETE FROM semantic_fts WHERE entity_type = 'content' AND entity_id = OLD.id;
                END;
            """)

            // Research triggers
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS research_fts_insert AFTER INSERT ON research
                WHEN NEW.is_deleted = 0
                BEGIN
                    INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                    VALUES ('research', NEW.id, COALESCE(NEW.title, ''), COALESCE(NEW.summary, ''), COALESCE(NEW.tags, ''));
                END;

                CREATE TRIGGER IF NOT EXISTS research_fts_update AFTER UPDATE ON research
                WHEN NEW.is_deleted = 0
                BEGIN
                    DELETE FROM semantic_fts WHERE entity_type = 'research' AND entity_id = OLD.id;
                    INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                    VALUES ('research', NEW.id, COALESCE(NEW.title, ''), COALESCE(NEW.summary, ''), COALESCE(NEW.tags, ''));
                END;

                CREATE TRIGGER IF NOT EXISTS research_fts_delete AFTER UPDATE ON research
                WHEN NEW.is_deleted = 1 AND OLD.is_deleted = 0
                BEGIN
                    DELETE FROM semantic_fts WHERE entity_type = 'research' AND entity_id = OLD.id;
                END;
            """)

            // Tasks triggers
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS tasks_fts_insert AFTER INSERT ON tasks
                WHEN NEW.is_deleted = 0
                BEGIN
                    INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                    VALUES ('task', NEW.id, COALESCE(NEW.title, ''), COALESCE(NEW.description, ''), '');
                END;

                CREATE TRIGGER IF NOT EXISTS tasks_fts_update AFTER UPDATE ON tasks
                WHEN NEW.is_deleted = 0
                BEGIN
                    DELETE FROM semantic_fts WHERE entity_type = 'task' AND entity_id = OLD.id;
                    INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                    VALUES ('task', NEW.id, COALESCE(NEW.title, ''), COALESCE(NEW.description, ''), '');
                END;

                CREATE TRIGGER IF NOT EXISTS tasks_fts_delete AFTER UPDATE ON tasks
                WHEN NEW.is_deleted = 1 AND OLD.is_deleted = 0
                BEGIN
                    DELETE FROM semantic_fts WHERE entity_type = 'task' AND entity_id = OLD.id;
                END;
            """)

            // Connections triggers
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS connections_fts_insert AFTER INSERT ON connections
                WHEN NEW.is_deleted = 0
                BEGIN
                    INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                    VALUES ('connection', NEW.id, COALESCE(NEW.title, ''),
                            COALESCE(NEW.idea, '') || ' ' || COALESCE(NEW.goal, '') || ' ' || COALESCE(NEW.problems, ''),
                            '');
                END;

                CREATE TRIGGER IF NOT EXISTS connections_fts_update AFTER UPDATE ON connections
                WHEN NEW.is_deleted = 0
                BEGIN
                    DELETE FROM semantic_fts WHERE entity_type = 'connection' AND entity_id = OLD.id;
                    INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                    VALUES ('connection', NEW.id, COALESCE(NEW.title, ''),
                            COALESCE(NEW.idea, '') || ' ' || COALESCE(NEW.goal, '') || ' ' || COALESCE(NEW.problems, ''),
                            '');
                END;

                CREATE TRIGGER IF NOT EXISTS connections_fts_delete AFTER UPDATE ON connections
                WHEN NEW.is_deleted = 1 AND OLD.is_deleted = 0
                BEGIN
                    DELETE FROM semantic_fts WHERE entity_type = 'connection' AND entity_id = OLD.id;
                END;
            """)

            print("✅ FTS sync triggers created successfully")
        }

        // Add Swipe File columns to research table for curated content collection
        // Enables global hotkey saving with auto-classification and semantic tagging
        migrator.registerMigration("add_swipe_file_columns") { db in
            print("🔨 Adding Swipe File columns to research table...")

            // Hook: The attention-grabbing opening line (required for swipe files)
            do {
                try db.execute(sql: "ALTER TABLE research ADD COLUMN hook TEXT")
                print("  ✅ Added hook column")
            } catch {
                print("  ⚠️ hook column may already exist: \(error.localizedDescription)")
            }

            // Emotion Tone: Categorizes the emotional impact of the content
            // Values: inspiring, provocative, vulnerable, educational, entertaining, controversial, motivational, analytical
            do {
                try db.execute(sql: "ALTER TABLE research ADD COLUMN emotion_tone TEXT")
                print("  ✅ Added emotion_tone column")
            } catch {
                print("  ⚠️ emotion_tone column may already exist: \(error.localizedDescription)")
            }

            // Structure Type: Categorizes the content format/structure
            // Values: story, breakdown, playbook, rant, hot_take, case_study, listicle, thread, tutorial, review
            do {
                try db.execute(sql: "ALTER TABLE research ADD COLUMN structure_type TEXT")
                print("  ✅ Added structure_type column")
            } catch {
                print("  ⚠️ structure_type column may already exist: \(error.localizedDescription)")
            }

            // Is Swipe File: Boolean flag to distinguish curated swipe items from research
            do {
                try db.execute(sql: "ALTER TABLE research ADD COLUMN is_swipe_file INTEGER DEFAULT 0")
                print("  ✅ Added is_swipe_file column")
            } catch {
                print("  ⚠️ is_swipe_file column may already exist: \(error.localizedDescription)")
            }

            // Content Source: How the item was captured
            // Values: clipboard, command_hub, share_extension, manual
            do {
                try db.execute(sql: "ALTER TABLE research ADD COLUMN content_source TEXT DEFAULT 'manual'")
                print("  ✅ Added content_source column")
            } catch {
                print("  ⚠️ content_source column may already exist: \(error.localizedDescription)")
            }

            // Create index for efficient swipe file queries
            do {
                try db.execute(sql: """
                    CREATE INDEX IF NOT EXISTS idx_research_swipe_file
                    ON research(is_swipe_file, emotion_tone, structure_type, created_at DESC)
                    WHERE is_deleted = 0
                """)
                print("  ✅ Created swipe file index")
            } catch {
                print("  ⚠️ Swipe file index may already exist: \(error.localizedDescription)")
            }

            // Update FTS triggers to include hook in search content
            // Drop and recreate the research update trigger
            do {
                try db.execute(sql: "DROP TRIGGER IF EXISTS research_fts_update")
                try db.execute(sql: """
                    CREATE TRIGGER research_fts_update AFTER UPDATE ON research
                    WHEN NEW.is_deleted = 0
                    BEGIN
                        DELETE FROM semantic_fts WHERE entity_type = 'research' AND entity_id = OLD.id;
                        INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                        VALUES ('research', NEW.id,
                                COALESCE(NEW.title, '') || ' ' || COALESCE(NEW.hook, ''),
                                COALESCE(NEW.summary, ''),
                                COALESCE(NEW.tags, ''));
                    END
                """)
                print("  ✅ Updated FTS trigger to include hook")
            } catch {
                print("  ⚠️ Failed to update FTS trigger: \(error.localizedDescription)")
            }

            print("✅ Swipe File migration complete")
        }

        // Create schedule_blocks table for the new dual-mode scheduler (Plan/Today)
        // This replaces the calendar_events table as the primary scheduling system
        migrator.registerMigration("create_schedule_blocks") { db in
            print("🔨 Creating schedule_blocks table for new scheduler...")

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS schedule_blocks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    uuid TEXT NOT NULL UNIQUE,
                    user_id TEXT,

                    -- Core fields
                    title TEXT NOT NULL,
                    block_type TEXT NOT NULL DEFAULT 'task',
                    notes TEXT,

                    -- Scheduling
                    start_time TEXT,
                    end_time TEXT,
                    duration_minutes INTEGER,
                    is_all_day INTEGER DEFAULT 0,

                    -- Status
                    status TEXT DEFAULT 'todo',
                    is_completed INTEGER DEFAULT 0,
                    completed_at TEXT,

                    -- Organization
                    project_id INTEGER,
                    project_uuid TEXT,
                    priority TEXT DEFAULT 'medium',
                    color TEXT,

                    -- Checklist (JSON array)
                    checklist TEXT,

                    -- Focus session data (JSON)
                    focus_session_data TEXT,

                    -- Recurrence (JSON)
                    recurrence TEXT,

                    -- Semantic links (JSON - ideas, research, connections)
                    semantic_links TEXT,

                    -- Origin tracking
                    origin_type TEXT,
                    origin_entity_type TEXT,
                    origin_entity_id INTEGER,
                    origin_entity_uuid TEXT,

                    -- Lifecycle
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    synced_at TEXT,
                    is_deleted INTEGER DEFAULT 0,

                    -- Sync tracking
                    _local_version INTEGER DEFAULT 1,
                    _server_version INTEGER DEFAULT 0,
                    _sync_version INTEGER DEFAULT 0,

                    FOREIGN KEY (project_id) REFERENCES projects(id)
                );

                -- Performance indexes
                CREATE INDEX IF NOT EXISTS idx_schedule_blocks_uuid
                    ON schedule_blocks(uuid);

                CREATE INDEX IF NOT EXISTS idx_schedule_blocks_start_time
                    ON schedule_blocks(start_time)
                    WHERE is_deleted = 0;

                CREATE INDEX IF NOT EXISTS idx_schedule_blocks_status
                    ON schedule_blocks(status, is_completed)
                    WHERE is_deleted = 0;

                CREATE INDEX IF NOT EXISTS idx_schedule_blocks_project
                    ON schedule_blocks(project_id)
                    WHERE is_deleted = 0;

                CREATE INDEX IF NOT EXISTS idx_schedule_blocks_type
                    ON schedule_blocks(block_type)
                    WHERE is_deleted = 0;

                CREATE INDEX IF NOT EXISTS idx_schedule_blocks_scheduled_range
                    ON schedule_blocks(start_time, end_time)
                    WHERE is_deleted = 0 AND start_time IS NOT NULL;

                CREATE INDEX IF NOT EXISTS idx_schedule_blocks_unscheduled
                    ON schedule_blocks(block_type, is_completed, is_deleted)
                    WHERE start_time IS NULL;
            """)

            print("  ✅ Created schedule_blocks table")

            // Add FTS trigger for schedule_blocks
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS schedule_blocks_fts_insert AFTER INSERT ON schedule_blocks
                WHEN NEW.is_deleted = 0
                BEGIN
                    INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                    VALUES ('schedule_block', NEW.id, COALESCE(NEW.title, ''), COALESCE(NEW.notes, ''), '');
                END;

                CREATE TRIGGER IF NOT EXISTS schedule_blocks_fts_update AFTER UPDATE ON schedule_blocks
                WHEN NEW.is_deleted = 0
                BEGIN
                    DELETE FROM semantic_fts WHERE entity_type = 'schedule_block' AND entity_id = OLD.id;
                    INSERT INTO semantic_fts(entity_type, entity_id, title, content, tags)
                    VALUES ('schedule_block', NEW.id, COALESCE(NEW.title, ''), COALESCE(NEW.notes, ''), '');
                END;

                CREATE TRIGGER IF NOT EXISTS schedule_blocks_fts_delete AFTER UPDATE ON schedule_blocks
                WHEN NEW.is_deleted = 1 AND OLD.is_deleted = 0
                BEGIN
                    DELETE FROM semantic_fts WHERE entity_type = 'schedule_block' AND entity_id = OLD.id;
                END;
            """)

            print("  ✅ Created FTS triggers for schedule_blocks")
            print("✅ Schedule blocks migration complete")
        }

        // Add description column to schedule_blocks if missing
        // The ScheduleBlock model expects 'description' but original schema only had 'notes'
        migrator.registerMigration("add_description_to_schedule_blocks") { db in
            print("🔨 Adding description column to schedule_blocks...")

            // Check if column already exists
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(schedule_blocks)")
            let columnNames = columns.compactMap { $0["name"] as? String }

            if !columnNames.contains("description") {
                try db.execute(sql: """
                    ALTER TABLE schedule_blocks ADD COLUMN description TEXT;
                """)
                print("  ✅ Added description column")
            } else {
                print("  ℹ️ description column already exists")
            }

            print("✅ schedule_blocks description migration complete")
        }

        // Add missing columns to schedule_blocks that the ScheduleBlock model expects
        // This fixes: tags, reminder_minutes, location, focus_session
        migrator.registerMigration("add_missing_schedule_blocks_columns") { db in
            print("🔨 Adding missing columns to schedule_blocks...")

            // Check existing columns
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(schedule_blocks)")
            let columnNames = Set(columns.compactMap { $0["name"] as? String })

            // Add tags column (JSON array of strings)
            if !columnNames.contains("tags") {
                try db.execute(sql: "ALTER TABLE schedule_blocks ADD COLUMN tags TEXT;")
                print("  ✅ Added tags column")
            }

            // Add reminder_minutes column
            if !columnNames.contains("reminder_minutes") {
                try db.execute(sql: "ALTER TABLE schedule_blocks ADD COLUMN reminder_minutes INTEGER;")
                print("  ✅ Added reminder_minutes column")
            }

            // Add location column
            if !columnNames.contains("location") {
                try db.execute(sql: "ALTER TABLE schedule_blocks ADD COLUMN location TEXT;")
                print("  ✅ Added location column")
            }

            // Add focus_session column (the model expects 'focus_session', not 'focus_session_data')
            if !columnNames.contains("focus_session") {
                try db.execute(sql: "ALTER TABLE schedule_blocks ADD COLUMN focus_session TEXT;")
                print("  ✅ Added focus_session column")
            }

            // Add recurrence_parent_id column
            if !columnNames.contains("recurrence_parent_id") {
                try db.execute(sql: "ALTER TABLE schedule_blocks ADD COLUMN recurrence_parent_id INTEGER;")
                print("  ✅ Added recurrence_parent_id column")
            }

            // Add recurrence_parent_uuid column
            if !columnNames.contains("recurrence_parent_uuid") {
                try db.execute(sql: "ALTER TABLE schedule_blocks ADD COLUMN recurrence_parent_uuid TEXT;")
                print("  ✅ Added recurrence_parent_uuid column")
            }

            print("✅ schedule_blocks missing columns migration complete")
        }

        // Add recurrence parent columns to schedule_blocks
        migrator.registerMigration("add_recurrence_parent_columns") { db in
            print("🔨 Adding recurrence parent columns to schedule_blocks...")

            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(schedule_blocks)")
            let columnNames = Set(columns.compactMap { $0["name"] as? String })

            if !columnNames.contains("recurrence_parent_id") {
                try db.execute(sql: "ALTER TABLE schedule_blocks ADD COLUMN recurrence_parent_id INTEGER;")
                print("  ✅ Added recurrence_parent_id column")
            }

            if !columnNames.contains("recurrence_parent_uuid") {
                try db.execute(sql: "ALTER TABLE schedule_blocks ADD COLUMN recurrence_parent_uuid TEXT;")
                print("  ✅ Added recurrence_parent_uuid column")
            }

            print("✅ Recurrence parent columns migration complete")
        }

        // ═══════════════════════════════════════════════════════════════════════
        // ATOM MIGRATION PHASE 1: Create atoms table
        // This is the foundation for the unified entity model
        // ═══════════════════════════════════════════════════════════════════════
        migrator.registerMigration("create_atoms_table") { db in
            print("🔨 Creating unified atoms table...")

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS atoms (
                    -- Core identity
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    uuid TEXT UNIQUE NOT NULL,
                    type TEXT NOT NULL,

                    -- Common fields (denormalized for query performance)
                    title TEXT,
                    body TEXT,

                    -- Flexible storage (JSON columns)
                    structured TEXT,
                    metadata TEXT,
                    links TEXT,

                    -- Timestamps
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at TEXT NOT NULL DEFAULT (datetime('now')),

                    -- Soft delete
                    is_deleted INTEGER DEFAULT 0,

                    -- Sync tracking
                    _local_version INTEGER DEFAULT 1,
                    _server_version INTEGER DEFAULT 0,
                    _sync_version INTEGER DEFAULT 0,
                    _local_pending INTEGER DEFAULT 0
                );

                -- Performance indexes
                CREATE INDEX IF NOT EXISTS idx_atoms_uuid ON atoms(uuid);
                CREATE INDEX IF NOT EXISTS idx_atoms_type ON atoms(type);
                CREATE INDEX IF NOT EXISTS idx_atoms_updated_at ON atoms(updated_at DESC);
                CREATE INDEX IF NOT EXISTS idx_atoms_type_deleted ON atoms(type, is_deleted);
                CREATE INDEX IF NOT EXISTS idx_atoms_type_updated ON atoms(type, updated_at DESC) WHERE is_deleted = 0;
            """)

            print("✅ Atoms table created successfully")
        }

        // ═══════════════════════════════════════════════════════════════════════
        // ATOM MIGRATION PHASE 2: Migrate legacy data to atoms
        // Safe to run multiple times - uses INSERT OR IGNORE pattern
        // ═══════════════════════════════════════════════════════════════════════
        migrator.registerMigration("migrate_legacy_to_atoms") { db in
            print("🔨 Migrating legacy entities to atoms table...")
            try AtomMigration.migrateAllToAtoms(db)
            print("✅ Legacy data migration complete")
        }

        // ═══════════════════════════════════════════════════════════════════════
        // ATOM MIGRATION PHASE 3: Create FTS for atoms
        // Replaces the old per-table FTS with a unified atom-based index
        // ═══════════════════════════════════════════════════════════════════════
        migrator.registerMigration("create_atoms_fts") { db in
            print("🔨 Creating FTS5 index for atoms...")

            // Create new FTS table for atoms
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS atoms_fts USING fts5(
                    uuid UNINDEXED,
                    type UNINDEXED,
                    title,
                    body,
                    metadata,
                    tokenize='porter unicode61 remove_diacritics 1'
                );
            """)

            // Populate from atoms table
            try db.execute(sql: """
                INSERT INTO atoms_fts(uuid, type, title, body, metadata)
                SELECT uuid, type, COALESCE(title, ''), COALESCE(body, ''), COALESCE(metadata, '')
                FROM atoms WHERE is_deleted = 0;
            """)

            // Create triggers to keep FTS in sync
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS atoms_fts_insert AFTER INSERT ON atoms
                WHEN NEW.is_deleted = 0
                BEGIN
                    INSERT INTO atoms_fts(uuid, type, title, body, metadata)
                    VALUES (NEW.uuid, NEW.type, COALESCE(NEW.title, ''), COALESCE(NEW.body, ''), COALESCE(NEW.metadata, ''));
                END;

                CREATE TRIGGER IF NOT EXISTS atoms_fts_update AFTER UPDATE ON atoms
                WHEN NEW.is_deleted = 0
                BEGIN
                    DELETE FROM atoms_fts WHERE uuid = OLD.uuid;
                    INSERT INTO atoms_fts(uuid, type, title, body, metadata)
                    VALUES (NEW.uuid, NEW.type, COALESCE(NEW.title, ''), COALESCE(NEW.body, ''), COALESCE(NEW.metadata, ''));
                END;

                CREATE TRIGGER IF NOT EXISTS atoms_fts_delete AFTER UPDATE ON atoms
                WHEN NEW.is_deleted = 1 AND OLD.is_deleted = 0
                BEGIN
                    DELETE FROM atoms_fts WHERE uuid = OLD.uuid;
                END;

                CREATE TRIGGER IF NOT EXISTS atoms_fts_hard_delete AFTER DELETE ON atoms
                BEGIN
                    DELETE FROM atoms_fts WHERE uuid = OLD.uuid;
                END;
            """)

            print("✅ Atoms FTS index created successfully")
        }

        // ═══════════════════════════════════════════════════════════════════════
        // ATOM MIGRATION PHASE 4: Update semantic_chunks to use UUID references
        // Adds entity_uuid column and migrates from integer IDs
        // ═══════════════════════════════════════════════════════════════════════
        migrator.registerMigration("semantic_chunks_uuid_migration") { db in
            print("🔨 Migrating semantic_chunks to UUID references...")

            // Check if entity_uuid column already exists
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(semantic_chunks)")
            let columnNames = Set(columns.compactMap { $0["name"] as? String })

            if !columnNames.contains("entity_uuid") {
                // Add entity_uuid column
                try db.execute(sql: "ALTER TABLE semantic_chunks ADD COLUMN entity_uuid TEXT;")
                print("  ✅ Added entity_uuid column to semantic_chunks")

                // Build UUID lookup and populate entity_uuid
                let lookup = try AtomMigration.buildUuidLookup(db)

                // Update semantic_chunks with UUIDs from legacy tables
                for (table, idToUuid) in lookup {
                    let entityType = table.singularized() // e.g., "ideas" -> "idea"
                    for (legacyId, uuid) in idToUuid {
                        try db.execute(
                            sql: """
                            UPDATE semantic_chunks
                            SET entity_uuid = ?
                            WHERE entity_type = ? AND entity_id = ?
                            """,
                            arguments: [uuid, entityType, legacyId]
                        )
                    }
                }
                print("  ✅ Populated entity_uuid from legacy tables")

                // Create index on entity_uuid
                try db.execute(sql: """
                    CREATE INDEX IF NOT EXISTS idx_semantic_chunks_entity_uuid
                    ON semantic_chunks(entity_uuid);
                """)
                print("  ✅ Created index on entity_uuid")
            }

            print("✅ semantic_chunks UUID migration complete")
        }

        // ═══════════════════════════════════════════════════════════════════════
        // ATOM MIGRATION PHASE 5: Update canvas_blocks to use UUID references
        // Ensures all entity references use UUIDs instead of integer IDs
        // ═══════════════════════════════════════════════════════════════════════
        migrator.registerMigration("canvas_blocks_uuid_migration") { db in
            print("🔨 Ensuring canvas_blocks uses UUID references...")

            // canvas_blocks already has entity_uuid, but verify and populate if needed
            let lookup = try AtomMigration.buildUuidLookup(db)

            // Update any canvas_blocks where entity_uuid is NULL but entity_id exists
            for (table, idToUuid) in lookup {
                let entityType = table.singularized()
                for (legacyId, uuid) in idToUuid {
                    try db.execute(
                        sql: """
                        UPDATE canvas_blocks
                        SET entity_uuid = ?
                        WHERE entity_type = ? AND entity_id = ? AND (entity_uuid IS NULL OR entity_uuid = '')
                        """,
                        arguments: [uuid, entityType, legacyId]
                    )
                }
            }

            // Also update document_uuid if missing
            for (_, idToUuid) in lookup {
                for (legacyId, uuid) in idToUuid {
                    try db.execute(
                        sql: """
                        UPDATE canvas_blocks
                        SET document_uuid = ?
                        WHERE document_id = ? AND (document_uuid IS NULL OR document_uuid = '')
                        """,
                        arguments: [uuid, legacyId]
                    )
                }
            }

            print("✅ canvas_blocks UUID migration complete")
        }

        // ═══════════════════════════════════════════════════════════════════════
        // ATOM MIGRATION PHASE 6 (FINAL): Drop legacy integer ID columns
        // This phase runs ONLY after confirming all references use UUIDs
        // Currently disabled - enable when ready for final cleanup
        // ═══════════════════════════════════════════════════════════════════════
        migrator.registerMigration("finalize_uuid_migration") { db in
            print("🔨 Finalizing UUID-only architecture...")

            // Verify all semantic_chunks have entity_uuid populated
            let missingSemanticUuids = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM semantic_chunks WHERE entity_uuid IS NULL OR entity_uuid = ''"
            ) ?? 0

            if missingSemanticUuids > 0 {
                print("  ⚠️ \(missingSemanticUuids) semantic_chunks still missing entity_uuid - skipping final cleanup")
                return
            }

            // Verify all canvas_blocks have entity_uuid populated
            let missingCanvasUuids = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM canvas_blocks WHERE entity_uuid IS NULL OR entity_uuid = ''"
            ) ?? 0

            if missingCanvasUuids > 0 {
                print("  ⚠️ \(missingCanvasUuids) canvas_blocks still missing entity_uuid - skipping final cleanup")
                return
            }

            print("  ✅ All references verified - UUID-only architecture complete")
            print("  ℹ️ Legacy tables preserved for reference (not deleted)")

            // Note: We do NOT drop legacy tables here
            // They remain as read-only archives until explicitly removed
            // The atoms table is now the source of truth

            print("✅ UUID migration finalized")
        }

        // ═══════════════════════════════════════════════════════════════════════
        // COSMO LEVEL SYSTEM MIGRATION: Performance indices for leveling atoms
        // Adds indices optimized for XP queries, streak tracking, and dimension analysis
        // ═══════════════════════════════════════════════════════════════════════
        migrator.registerMigration("cosmo_level_system_indices") { db in
            print("🔨 Creating Cosmo Level System performance indices...")

            // ── XP Event Indices ──
            // Query pattern: Get all XP events for a dimension in a date range
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_atoms_xp_events
                ON atoms(type, created_at DESC)
                WHERE type = 'xp_event' AND is_deleted = 0;
            """)
            print("  ✅ Created XP events index")

            // ── Streak Event Indices ──
            // Query pattern: Get active streaks, streak milestones
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_atoms_streak_events
                ON atoms(type, created_at DESC)
                WHERE type = 'streak_event' AND is_deleted = 0;
            """)
            print("  ✅ Created streak events index")

            // ── Badge Unlock Indices ──
            // Query pattern: Get unlocked badges, check badge status
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_atoms_badges
                ON atoms(type, created_at DESC)
                WHERE type = 'badge_unlocked' AND is_deleted = 0;
            """)
            print("  ✅ Created badges index")

            // ── Level Update Indices ──
            // Query pattern: Get level history, current level state
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_atoms_level_updates
                ON atoms(type, created_at DESC)
                WHERE type = 'level_update' AND is_deleted = 0;
            """)
            print("  ✅ Created level updates index")

            // ── Dimension Snapshot Indices ──
            // Query pattern: Get daily dimension scores, trend analysis
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_atoms_dimension_snapshots
                ON atoms(type, created_at DESC)
                WHERE type = 'dimension_snapshot' AND is_deleted = 0;
            """)
            print("  ✅ Created dimension snapshots index")

            // ── Physiology Atom Indices ──
            // Query pattern: Get HRV/sleep/workout data by date
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_atoms_physiology
                ON atoms(type, created_at DESC)
                WHERE type IN ('hrv_measurement', 'resting_hr', 'sleep_cycle',
                              'sleep_consistency', 'readiness_score', 'workout_session',
                              'breathing_session', 'blood_oxygen', 'body_temperature')
                AND is_deleted = 0;
            """)
            print("  ✅ Created physiology atoms index")

            // ── Cognitive Output Indices ──
            // Query pattern: Get deep work blocks, writing sessions by date
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_atoms_cognitive
                ON atoms(type, created_at DESC)
                WHERE type IN ('deep_work_block', 'writing_session', 'word_count_entry',
                              'focus_score', 'distraction_event')
                AND is_deleted = 0;
            """)
            print("  ✅ Created cognitive atoms index")

            // ── Content Pipeline Indices ──
            // Query pattern: Track content through phases, performance
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_atoms_content_pipeline
                ON atoms(type, created_at DESC)
                WHERE type IN ('content_draft', 'content_phase', 'content_performance',
                              'content_publish', 'client_profile')
                AND is_deleted = 0;
            """)
            print("  ✅ Created content pipeline index")

            // ── Reflection Indices ──
            // Query pattern: Get journal insights, emotional states
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_atoms_reflection
                ON atoms(type, created_at DESC)
                WHERE type IN ('journal_insight', 'analysis_chunk', 'emotional_state',
                              'clarity_score')
                AND is_deleted = 0;
            """)
            print("  ✅ Created reflection atoms index")

            // ── Daily/Weekly Summary Indices ──
            // Query pattern: Get summaries by date
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_atoms_summaries
                ON atoms(type, created_at DESC)
                WHERE type IN ('daily_summary', 'weekly_summary')
                AND is_deleted = 0;
            """)
            print("  ✅ Created summaries index")

            // ── Knowledge Graph Indices ──
            // Query pattern: Navigate semantic clusters, link suggestions
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_atoms_knowledge_graph
                ON atoms(type, created_at DESC)
                WHERE type IN ('semantic_cluster', 'connection_link', 'auto_link_suggestion',
                              'insight_extraction')
                AND is_deleted = 0;
            """)
            print("  ✅ Created knowledge graph index")

            // ── Routine/Behavioral Indices ──
            // Query pattern: Get active routines, routine instances
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_atoms_routines
                ON atoms(type, created_at DESC)
                WHERE type = 'routine_definition' AND is_deleted = 0;
            """)
            print("  ✅ Created routines index")

            // ── Composite Index for Metadata JSON Queries ──
            // While SQLite can't directly index JSON, we can create a generated column
            // and index that for common query patterns. This is optional and can be
            // added later if query performance requires it.

            print("✅ Cosmo Level System indices created successfully")
        }

        // ═══════════════════════════════════════════════════════════════════════
        // COSMO LEVEL SYSTEM CACHE: State table for fast level queries
        // This is a denormalized cache for current user state - rebuilt from atoms
        // ═══════════════════════════════════════════════════════════════════════
        migrator.registerMigration("cosmo_level_state_cache") { db in
            print("🔨 Creating Cosmo Level System state cache...")

            // Create a cache table for current level state
            // This is rebuilt from atoms but provides fast access to current state
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS cosmo_level_state (
                    id INTEGER PRIMARY KEY,

                    -- Overall scores
                    cosmo_index INTEGER DEFAULT 0,
                    overall_nelo INTEGER DEFAULT 1200,

                    -- Dimension CI (permanent XP progression)
                    cognitive_ci INTEGER DEFAULT 0,
                    creative_ci INTEGER DEFAULT 0,
                    physiological_ci INTEGER DEFAULT 0,
                    behavioral_ci INTEGER DEFAULT 0,
                    knowledge_ci INTEGER DEFAULT 0,
                    reflection_ci INTEGER DEFAULT 0,

                    -- Dimension NELO (dynamic performance rating)
                    cognitive_nelo INTEGER DEFAULT 1200,
                    creative_nelo INTEGER DEFAULT 1200,
                    physiological_nelo INTEGER DEFAULT 1200,
                    behavioral_nelo INTEGER DEFAULT 1200,
                    knowledge_nelo INTEGER DEFAULT 1200,
                    reflection_nelo INTEGER DEFAULT 1200,

                    -- Dimension Levels (derived from CI)
                    cognitive_level INTEGER DEFAULT 1,
                    creative_level INTEGER DEFAULT 1,
                    physiological_level INTEGER DEFAULT 1,
                    behavioral_level INTEGER DEFAULT 1,
                    knowledge_level INTEGER DEFAULT 1,
                    reflection_level INTEGER DEFAULT 1,

                    -- Active Streaks (JSON object)
                    active_streaks TEXT DEFAULT '{}',

                    -- Badge Count by Category (JSON object)
                    badge_counts TEXT DEFAULT '{}',

                    -- Total Stats
                    total_xp_earned INTEGER DEFAULT 0,
                    total_badges_unlocked INTEGER DEFAULT 0,
                    longest_streak_ever INTEGER DEFAULT 0,

                    -- Timestamps
                    last_xp_at TEXT,
                    last_level_up_at TEXT,
                    last_badge_at TEXT,
                    updated_at TEXT NOT NULL DEFAULT (datetime('now')),

                    -- Ensure single row
                    CONSTRAINT single_row CHECK (id = 1)
                );

                -- Insert initial state row
                INSERT OR IGNORE INTO cosmo_level_state (id) VALUES (1);
            """)
            print("  ✅ Created level state cache table")

            // Create streak tracking cache for fast streak queries
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS cosmo_streak_cache (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    streak_type TEXT NOT NULL UNIQUE,
                    current_count INTEGER DEFAULT 0,
                    longest_count INTEGER DEFAULT 0,
                    last_activity_date TEXT,
                    multiplier REAL DEFAULT 1.0,
                    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
                );

                -- Create indices for streak queries
                CREATE INDEX IF NOT EXISTS idx_streak_type
                ON cosmo_streak_cache(streak_type);
            """)
            print("  ✅ Created streak cache table")

            // Create badge status cache for fast badge lookups
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS cosmo_badge_cache (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    badge_id TEXT NOT NULL UNIQUE,
                    category TEXT NOT NULL,
                    tier TEXT NOT NULL,
                    unlocked INTEGER DEFAULT 0,
                    unlocked_at TEXT,
                    progress REAL DEFAULT 0.0,
                    progress_current INTEGER DEFAULT 0,
                    progress_target INTEGER NOT NULL,
                    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
                );

                -- Create indices for badge queries
                CREATE INDEX IF NOT EXISTS idx_badge_category
                ON cosmo_badge_cache(category, unlocked);

                CREATE INDEX IF NOT EXISTS idx_badge_unlocked
                ON cosmo_badge_cache(unlocked, unlocked_at DESC);
            """)
            print("  ✅ Created badge cache table")

            print("✅ Cosmo Level System state cache created successfully")
        }

        // ═══════════════════════════════════════════════════════════════════════
        // NODEGRAPH OS: Create graph tables for the constellation engine
        // graph_nodes: Wraps atoms with position/relevance metadata
        // graph_edges: Relationships between nodes (structural + semantic)
        // ═══════════════════════════════════════════════════════════════════════
        migrator.registerMigration("create_nodegraph_tables") { db in
            print("🔨 Creating NodeGraph OS tables...")

            // ── Graph Nodes Table ──
            // Each node references an Atom and caches visualization/ranking data
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS graph_nodes (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    atom_uuid TEXT NOT NULL UNIQUE,
                    atom_type TEXT NOT NULL,
                    atom_category TEXT NOT NULL,

                    -- Position hints for constellation visualization
                    position_x REAL,
                    position_y REAL,
                    cluster_hint TEXT,

                    -- Relevance cache for ranking
                    page_rank REAL DEFAULT 0.0,
                    in_degree INTEGER DEFAULT 0,
                    out_degree INTEGER DEFAULT 0,
                    access_count INTEGER DEFAULT 0,
                    last_accessed_at TEXT,

                    -- Embedding state
                    has_embedding INTEGER DEFAULT 0,
                    embedding_updated_at TEXT,

                    -- Timestamps
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                    atom_updated_at TEXT NOT NULL,

                    FOREIGN KEY (atom_uuid) REFERENCES atoms(uuid) ON DELETE CASCADE
                );

                -- Indexes for common queries
                CREATE INDEX IF NOT EXISTS idx_graph_nodes_type
                    ON graph_nodes(atom_type);
                CREATE INDEX IF NOT EXISTS idx_graph_nodes_category
                    ON graph_nodes(atom_category);
                CREATE INDEX IF NOT EXISTS idx_graph_nodes_page_rank
                    ON graph_nodes(page_rank DESC);
                CREATE INDEX IF NOT EXISTS idx_graph_nodes_cluster
                    ON graph_nodes(cluster_hint);
                CREATE INDEX IF NOT EXISTS idx_graph_nodes_access
                    ON graph_nodes(last_accessed_at DESC);
                CREATE INDEX IF NOT EXISTS idx_graph_nodes_embedding
                    ON graph_nodes(has_embedding);
            """)
            print("  ✅ Created graph_nodes table")

            // ── Graph Edges Table ──
            // Edges encode relationships: explicit (AtomLinks) + semantic (vector similarity)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS graph_edges (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_uuid TEXT NOT NULL,
                    target_uuid TEXT NOT NULL,

                    -- Edge properties
                    edge_type TEXT NOT NULL,
                    link_type TEXT,
                    is_directed INTEGER DEFAULT 1,

                    -- Weight components (formula: 0.55*semantic + 0.25*structural + 0.10*recency + 0.10*usage)
                    structural_weight REAL DEFAULT 0.0,
                    semantic_weight REAL DEFAULT 0.0,
                    recency_weight REAL DEFAULT 1.0,
                    usage_weight REAL DEFAULT 0.0,
                    combined_weight REAL DEFAULT 0.0,

                    -- Metadata
                    last_computed_at TEXT NOT NULL DEFAULT (datetime('now')),
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at TEXT NOT NULL DEFAULT (datetime('now')),

                    -- Composite unique constraint (directed edge uniqueness)
                    UNIQUE(source_uuid, target_uuid, edge_type),

                    FOREIGN KEY (source_uuid) REFERENCES graph_nodes(atom_uuid) ON DELETE CASCADE,
                    FOREIGN KEY (target_uuid) REFERENCES graph_nodes(atom_uuid) ON DELETE CASCADE
                );

                -- Indexes for graph traversal
                CREATE INDEX IF NOT EXISTS idx_graph_edges_source
                    ON graph_edges(source_uuid);
                CREATE INDEX IF NOT EXISTS idx_graph_edges_target
                    ON graph_edges(target_uuid);
                CREATE INDEX IF NOT EXISTS idx_graph_edges_type
                    ON graph_edges(edge_type);
                CREATE INDEX IF NOT EXISTS idx_graph_edges_weight
                    ON graph_edges(combined_weight DESC);
                CREATE INDEX IF NOT EXISTS idx_graph_edges_source_weight
                    ON graph_edges(source_uuid, combined_weight DESC);
                CREATE INDEX IF NOT EXISTS idx_graph_edges_target_weight
                    ON graph_edges(target_uuid, combined_weight DESC);
            """)
            print("  ✅ Created graph_edges table")

            print("✅ NodeGraph OS tables created successfully")
        }

        // ═══════════════════════════════════════════════════════════════════════
        // NODEGRAPH OS: Populate initial graph from existing atoms
        // Creates graph nodes for all non-deleted atoms
        // ═══════════════════════════════════════════════════════════════════════
        migrator.registerMigration("populate_initial_graph") { db in
            print("🔨 Populating initial graph from atoms...")

            // Insert graph nodes for all existing atoms
            try db.execute(sql: """
                INSERT OR IGNORE INTO graph_nodes (
                    atom_uuid,
                    atom_type,
                    atom_category,
                    page_rank,
                    in_degree,
                    out_degree,
                    access_count,
                    has_embedding,
                    created_at,
                    updated_at,
                    atom_updated_at
                )
                SELECT
                    uuid,
                    type,
                    CASE
                        WHEN type IN ('idea', 'task', 'uncommitted_item', 'canvas_block', 'thinkspace_node') THEN 'core'
                        WHEN type IN ('project', 'schedule_block', 'routine_definition', 'habit_tracker') THEN 'organization'
                        WHEN type IN ('content', 'content_draft', 'content_phase', 'content_publish') THEN 'content'
                        WHEN type IN ('research', 'semantic_cluster', 'auto_link_suggestion') THEN 'knowledge'
                        WHEN type IN ('connection', 'client_profile') THEN 'relationship'
                        WHEN type IN ('journal_entry', 'journal_insight', 'emotional_state') THEN 'reflection'
                        WHEN type IN ('hrv_measurement', 'sleep_cycle', 'workout_session') THEN 'physiology'
                        WHEN type IN ('xp_event', 'streak_event', 'badge_unlocked', 'level_update') THEN 'gamification'
                        ELSE 'system'
                    END,
                    0.0,
                    0,
                    0,
                    0,
                    0,
                    datetime('now'),
                    datetime('now'),
                    updated_at
                FROM atoms
                WHERE is_deleted = 0;
            """)
            print("  ✅ Inserted graph nodes for existing atoms")

            // Create explicit edges from AtomLinks in the links JSON column
            // Note: This is a simplified version - full edge population happens in NodeGraphEngine
            print("  ℹ️ Explicit edges will be populated by NodeGraphEngine on first run")

            print("✅ Initial graph population complete")
        }

        // ═══════════════════════════════════════════════════════════════════════
        // MIGRATION: Add thinkspace_id to canvas_blocks
        // Allows blocks to belong to a specific Thinkspace (saved canvas config)
        // ═══════════════════════════════════════════════════════════════════════
        migrator.registerMigration("add_thinkspace_id_to_canvas_blocks") { db in
            print("🔨 Adding thinkspace_id to canvas_blocks...")
            do {
                try db.execute(sql: "ALTER TABLE canvas_blocks ADD COLUMN thinkspace_id TEXT")
                print("  ✅ Added thinkspace_id to canvas_blocks")
            } catch {
                print("  ⚠️ thinkspace_id may already exist in canvas_blocks: \(error.localizedDescription)")
            }
            print("✅ thinkspace_id migration complete")
        }

        // Add is_pinned column to canvas_blocks for pinning blocks
        migrator.registerMigration("add_is_pinned_to_canvas_blocks") { db in
            print("🔨 Adding is_pinned to canvas_blocks...")
            do {
                try db.execute(sql: "ALTER TABLE canvas_blocks ADD COLUMN is_pinned INTEGER DEFAULT 0")
                print("  ✅ Added is_pinned to canvas_blocks")
            } catch {
                print("  ⚠️ is_pinned may already exist in canvas_blocks: \(error.localizedDescription)")
            }
            print("✅ is_pinned migration complete")
        }

        // Add _local_pending column to atoms table (separate migration since original may have already run)
        migrator.registerMigration("add_local_pending_to_atoms") { db in
            print("🔨 Adding _local_pending to atoms...")
            do {
                try db.execute(sql: "ALTER TABLE atoms ADD COLUMN _local_pending INTEGER DEFAULT 0")
                print("  ✅ Added _local_pending to atoms")
            } catch {
                print("  ⚠️ _local_pending may already exist in atoms: \(error.localizedDescription)")
            }
            print("✅ atoms _local_pending migration complete")
        }

        // Create canvas_drawings table for freeform drawing elements (shapes, freehand, text)
        migrator.registerMigration("create_canvas_drawings") { db in
            print("🔨 Creating canvas_drawings table...")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS canvas_drawings (
                    id TEXT PRIMARY KEY,
                    thinkspace_id TEXT,
                    drawing_type TEXT NOT NULL,
                    shape_kind TEXT,
                    origin_x REAL NOT NULL,
                    origin_y REAL NOT NULL,
                    width REAL,
                    height REAL,
                    rotation REAL DEFAULT 0,
                    path_data TEXT,
                    text_content TEXT,
                    text_weight TEXT,
                    stroke_color TEXT NOT NULL DEFAULT '#FFFFFF',
                    fill_color TEXT,
                    stroke_width REAL NOT NULL DEFAULT 2.0,
                    opacity REAL NOT NULL DEFAULT 1.0,
                    z_index INTEGER DEFAULT 0,
                    is_deleted INTEGER DEFAULT 0,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_canvas_drawings_thinkspace
                    ON canvas_drawings(thinkspace_id, is_deleted)
            """)
            print("✅ canvas_drawings table created")
        }

        // MARK: - Inbox Items
        migrator.registerMigration("create_inbox_items") { db in
            print("🔨 Creating inbox_items table...")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS inbox_items (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    uuid TEXT UNIQUE NOT NULL,
                    source TEXT NOT NULL,
                    rawText TEXT NOT NULL,
                    title TEXT,
                    classification TEXT,
                    confidence REAL DEFAULT 0.0,
                    mergeTargetUuid TEXT,
                    mergeTargetTitle TEXT,
                    mergeTargetType TEXT,
                    mergePreview TEXT,
                    placeThinkspaceId TEXT,
                    placeThinkspaceName TEXT,
                    placeAtomType TEXT,
                    recommendations TEXT,
                    primaryRouteKind TEXT,
                    destinationPath TEXT,
                    rationale TEXT,
                    placementPlanSummary TEXT,
                    status TEXT NOT NULL DEFAULT 'pending',
                    isRead INTEGER DEFAULT 0,
                    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
                    classifiedAt TEXT,
                    actionedAt TEXT,
                    metadata TEXT
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_inbox_items_status
                    ON inbox_items(status)
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_inbox_items_created
                    ON inbox_items(createdAt DESC)
            """)
            print("✅ inbox_items table created")
        }

        migrator.registerMigration("add_routing_columns_to_inbox_items") { db in
            print("🔨 Adding routing columns to inbox_items...")
            let statements = [
                "ALTER TABLE inbox_items ADD COLUMN recommendations TEXT",
                "ALTER TABLE inbox_items ADD COLUMN primaryRouteKind TEXT",
                "ALTER TABLE inbox_items ADD COLUMN destinationPath TEXT",
                "ALTER TABLE inbox_items ADD COLUMN rationale TEXT",
                "ALTER TABLE inbox_items ADD COLUMN placementPlanSummary TEXT"
            ]

            for statement in statements {
                do {
                    try db.execute(sql: statement)
                } catch {
                    print("  ⚠️ inbox_items routing column may already exist: \(error.localizedDescription)")
                }
            }
            print("✅ inbox_items routing migration complete")
        }

        // MARK: - Custom Capture Lanes
        migrator.registerMigration("create_custom_capture_lanes") { db in
            print("🔨 Creating custom capture lane tables...")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS capture_destinations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    uuid TEXT UNIQUE NOT NULL,
                    name TEXT NOT NULL,
                    destinationDescription TEXT,
                    type TEXT NOT NULL,
                    aliasesJSON TEXT NOT NULL DEFAULT '[]',
                    icon TEXT NOT NULL,
                    colorAccentToken TEXT,
                    defaultObjectType TEXT NOT NULL,
                    defaultParentTarget TEXT,
                    defaultReviewBehavior TEXT NOT NULL,
                    telegramCommandPatternsJSON TEXT,
                    acceptedMediaTypesJSON TEXT,
                    processingRulesJSON TEXT,
                    routingRulesJSON TEXT,
                    isArchived INTEGER NOT NULL DEFAULT 0,
                    isEnabled INTEGER NOT NULL DEFAULT 1,
                    createdAt TEXT NOT NULL,
                    updatedAt TEXT NOT NULL,
                    lastUsedAt TEXT,
                    itemCount INTEGER NOT NULL DEFAULT 0,
                    conflictStatus TEXT NOT NULL DEFAULT 'clear'
                );

                CREATE INDEX IF NOT EXISTS idx_capture_destinations_uuid
                    ON capture_destinations(uuid);
                CREATE INDEX IF NOT EXISTS idx_capture_destinations_enabled
                    ON capture_destinations(isEnabled, isArchived);
                CREATE INDEX IF NOT EXISTS idx_capture_destinations_last_used
                    ON capture_destinations(lastUsedAt DESC);

                CREATE TABLE IF NOT EXISTS captured_items (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    uuid TEXT UNIQUE NOT NULL,
                    rawText TEXT,
                    caption TEXT,
                    cleanText TEXT,
                    source TEXT NOT NULL,
                    telegramMessageId TEXT,
                    telegramMediaGroupId TEXT,
                    telegramChatId TEXT,
                    sender TEXT,
                    timestamp TEXT NOT NULL,
                    captureDestinationId TEXT,
                    parsedCommand TEXT,
                    parsedIntent TEXT,
                    mediaAttachmentIdsJSON TEXT,
                    createdObjectIdsJSON TEXT,
                    routingConfidence REAL NOT NULL DEFAULT 0.0,
                    status TEXT NOT NULL,
                    parentDeepDiveId TEXT,
                    parentInquirySessionId TEXT,
                    parentQuestionId TEXT,
                    parentProjectId TEXT,
                    provenanceMetadata TEXT,
                    createdAt TEXT NOT NULL,
                    updatedAt TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_captured_items_uuid
                    ON captured_items(uuid);
                CREATE INDEX IF NOT EXISTS idx_captured_items_destination
                    ON captured_items(captureDestinationId, createdAt DESC);
                CREATE INDEX IF NOT EXISTS idx_captured_items_status
                    ON captured_items(status, createdAt DESC);
                CREATE INDEX IF NOT EXISTS idx_captured_items_telegram_message
                    ON captured_items(telegramChatId, telegramMessageId);

                CREATE TABLE IF NOT EXISTS media_attachments (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    uuid TEXT UNIQUE NOT NULL,
                    capturedItemId TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    originalFilename TEXT,
                    mimeType TEXT,
                    fileSize INTEGER,
                    telegramFileId TEXT,
                    telegramFileUniqueId TEXT,
                    localStoragePath TEXT,
                    blobReference TEXT,
                    thumbnailPath TEXT,
                    extractedText TEXT,
                    transcriptText TEXT,
                    metadata TEXT,
                    processingStatus TEXT NOT NULL,
                    sourceObjectId TEXT,
                    createdAt TEXT NOT NULL,
                    updatedAt TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_media_attachments_uuid
                    ON media_attachments(uuid);
                CREATE INDEX IF NOT EXISTS idx_media_attachments_captured_item
                    ON media_attachments(capturedItemId);
                CREATE INDEX IF NOT EXISTS idx_media_attachments_status
                    ON media_attachments(processingStatus);
                CREATE INDEX IF NOT EXISTS idx_media_attachments_telegram_file
                    ON media_attachments(telegramFileUniqueId);
            """)
            print("✅ custom capture lane tables created")
        }

        // Clean up duplicate canvas_blocks rows that accumulated due to
        // saveBlock() generating new IDs instead of updating existing rows
        migrator.registerMigration("deduplicate_canvas_blocks") { db in
            print("🔨 Cleaning up duplicate canvas_blocks...")
            try db.execute(sql: """
                DELETE FROM canvas_blocks
                WHERE id NOT IN (
                    SELECT id FROM (
                        SELECT id, ROW_NUMBER() OVER (
                            PARTITION BY entity_uuid, COALESCE(thinkspace_id, ''), document_type, document_id
                            ORDER BY updated_at DESC, created_at DESC
                        ) AS rn
                        FROM canvas_blocks
                        WHERE entity_uuid IS NOT NULL AND entity_uuid != '' AND is_deleted = 0
                    )
                    WHERE rn = 1
                )
                AND entity_uuid IS NOT NULL AND entity_uuid != '' AND is_deleted = 0
            """)
            print("✅ Duplicate canvas_blocks cleanup complete")
        }

        // Add atom_uuid column to canvas_blocks (matches Supabase remote schema)
        migrator.registerMigration("add_atom_uuid_to_canvas_blocks") { db in
            print("🔨 Adding atom_uuid to canvas_blocks...")
            do {
                try db.execute(sql: "ALTER TABLE canvas_blocks ADD COLUMN atom_uuid TEXT")
                print("  ✅ Added atom_uuid to canvas_blocks")
            } catch {
                print("  ⚠️ atom_uuid may already exist in canvas_blocks: \(error.localizedDescription)")
            }
            print("✅ atom_uuid migration complete")
        }

        migrator.registerMigration("canvas_blocks_thinkspace_lookup_index") { db in
            print("🔨 Adding thinkspace lookup index to canvas_blocks...")
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_canvas_blocks_thinkspace_lookup
                ON canvas_blocks(thinkspace_id, is_deleted, z_index)
            """)
            print("✅ canvas_blocks thinkspace lookup index ready")
        }

        // Create automation_rules performance index table
        migrator.registerMigration("create_automation_rules") { db in
            print("🔨 Creating automation_rules table...")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS automation_rules (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    uuid TEXT NOT NULL UNIQUE,
                    name TEXT NOT NULL,
                    isEnabled INTEGER NOT NULL DEFAULT 1,
                    scope TEXT NOT NULL DEFAULT 'global',
                    scopeId TEXT,
                    triggerType TEXT NOT NULL,
                    triggerConfig TEXT NOT NULL DEFAULT '{}',
                    conditions TEXT,
                    conditionLogic TEXT NOT NULL DEFAULT 'all',
                    actions TEXT NOT NULL DEFAULT '[]',
                    priority INTEGER NOT NULL DEFAULT 50,
                    cooldownSeconds INTEGER NOT NULL DEFAULT 1,
                    lastFiredAt TEXT,
                    fireCount INTEGER NOT NULL DEFAULT 0,
                    maxFires INTEGER,
                    isBuiltIn INTEGER NOT NULL DEFAULT 0,
                    createdAt TEXT NOT NULL,
                    updatedAt TEXT NOT NULL
                )
            """)
            // Index for fast trigger-type lookup (the primary query path)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_automation_rules_trigger
                ON automation_rules(triggerType, isEnabled)
            """)
            // Index for scope-based queries
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_automation_rules_scope
                ON automation_rules(scope, scopeId)
            """)
            print("✅ automation_rules table created")
        }

        // FIX 1 [P0]: Create sync support tables that SyncEngine depends on
        // sync_fence prevents echo loops; user_settings stores last pull timestamps
        migrator.registerMigration("create_sync_support_tables") { db in
            print("🔨 Creating sync support tables...")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS sync_fence (
                    uuid TEXT PRIMARY KEY NOT NULL,
                    expires_at INTEGER NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_sync_fence_expires
                ON sync_fence(expires_at)
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS user_settings (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT
                )
            """)
            print("✅ sync_fence + user_settings tables created")
        }

        migrator.registerMigration("create_custom_agent_profiles") { db in
            print("🔨 Creating custom_agent_profiles table...")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS custom_agent_profiles (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    icon TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    runtime_prompt TEXT NOT NULL,
                    seed_prompts TEXT NOT NULL DEFAULT '[]',
                    tool_bundles TEXT NOT NULL,
                    context_scopes TEXT NOT NULL,
                    preferred_model_tier TEXT,
                    is_enabled INTEGER NOT NULL DEFAULT 1,
                    is_builtin INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    is_deleted INTEGER NOT NULL DEFAULT 0,
                    _local_version INTEGER DEFAULT 1,
                    _server_version INTEGER DEFAULT 0,
                    _sync_version INTEGER DEFAULT 0,
                    _local_pending INTEGER DEFAULT 0
                );

                CREATE INDEX IF NOT EXISTS idx_custom_agent_profiles_enabled
                    ON custom_agent_profiles(is_enabled, is_deleted);
                CREATE INDEX IF NOT EXISTS idx_custom_agent_profiles_updated
                    ON custom_agent_profiles(updated_at DESC);
            """)
            print("✅ custom_agent_profiles table created")
        }

        migrator.registerMigration("add_seed_prompts_to_custom_agent_profiles") { db in
            print("🔨 Adding seed_prompts to custom_agent_profiles...")
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(custom_agent_profiles)")
            let columnNames = Set(columns.compactMap { $0["name"] as? String })

            if !columnNames.contains("seed_prompts") {
                try db.execute(sql: "ALTER TABLE custom_agent_profiles ADD COLUMN seed_prompts TEXT NOT NULL DEFAULT '[]'")
                print("  ✅ Added seed_prompts")
            } else {
                print("  ℹ️ seed_prompts already exists")
            }
            print("✅ custom_agent_profiles seed prompts migration complete")
        }

        migrator.registerMigration("create_context_index_tables") { db in
            print("🔨 Creating shared context index tables...")
            try Self.createContextIndexSchema(db)
            print("✅ shared context index tables created")
        }

        migrator.registerMigration("create_context_session_tables") { db in
            print("🔨 Creating shared context session tables...")
            try Self.createContextSessionSchema(db)
            print("✅ shared context session tables created")
        }

        migrator.registerMigration("create_inline_assistant_skills") { db in
            print("🔨 Creating inline_assistant_skills table...")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS inline_assistant_skills (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    definition TEXT NOT NULL,
                    trigger_embedding BLOB,
                    is_enabled INTEGER NOT NULL DEFAULT 1,
                    is_builtin INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    is_deleted INTEGER NOT NULL DEFAULT 0,
                    _local_version INTEGER DEFAULT 1,
                    _server_version INTEGER DEFAULT 0,
                    _sync_version INTEGER DEFAULT 0,
                    _local_pending INTEGER DEFAULT 0
                );

                CREATE INDEX IF NOT EXISTS idx_inline_assistant_skills_enabled
                    ON inline_assistant_skills(is_enabled, is_deleted);
                CREATE INDEX IF NOT EXISTS idx_inline_assistant_skills_updated
                    ON inline_assistant_skills(updated_at DESC);
            """)
            print("✅ inline_assistant_skills table created")
        }

        migrator.registerMigration("create_flow_firings") { db in
            print("🔨 Creating flow_firings table...")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS flow_firings (
                    uuid TEXT PRIMARY KEY NOT NULL,
                    flowUUID TEXT NOT NULL,
                    thinkspaceId TEXT,
                    summary TEXT NOT NULL,
                    outputAtomUUID TEXT,
                    createdAt TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_flow_firings_flow
                    ON flow_firings(flowUUID, createdAt DESC);
            """)
            print("✅ flow_firings table created")
        }

        migrator.registerMigration("create_workbenches") { db in
            print("🔨 Creating workbenches table...")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS workbenches (
                    uuid TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    glyph TEXT NOT NULL,
                    tintHex TEXT NOT NULL,
                    snapshot TEXT NOT NULL,
                    sortOrder INTEGER NOT NULL DEFAULT 0,
                    lastUsedAt TEXT,
                    useCount INTEGER NOT NULL DEFAULT 0,
                    createdAt TEXT NOT NULL
                );
            """)
            print("✅ workbenches table created")
        }

        migrator.registerMigration("create_swipe_boards") { db in
            print("🔨 Creating swipe_boards table...")
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS swipe_boards (
                    uuid TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    icon TEXT NOT NULL,
                    tintToken TEXT,
                    sortOrder INTEGER NOT NULL DEFAULT 0,
                    isArchived INTEGER NOT NULL DEFAULT 0,
                    createdAt TEXT NOT NULL,
                    updatedAt TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_swipe_boards_active
                    ON swipe_boards(isArchived, sortOrder);
            """)

            // Seed the legacy sidebar boards with their historical slug ids so any
            // swipeBoardIDs already persisted on atoms keep resolving.
            let now = ISO8601DateFormatter().string(from: Date())
            let seeds: [(uuid: String, name: String, icon: String, order: Int)] = [
                ("thread-hooks", "Thread Hooks", "text.alignleft", 0),
                ("reel-ideas", "Reel Ideas", "play.rectangle", 1),
                ("client-proof", "Client Proof", "checkmark.seal", 2)
            ]
            for seed in seeds {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO swipe_boards
                            (uuid, name, icon, sortOrder, isArchived, createdAt, updatedAt)
                        VALUES (?, ?, ?, ?, 0, ?, ?)
                    """,
                    arguments: [seed.uuid, seed.name, seed.icon, seed.order, now, now]
                )
            }
            print("✅ swipe_boards table created")
        }

        migrator.registerMigration("create_app_flags") { db in
            // Durable key-value flags that must live in the DATABASE, not
            // UserDefaults — one-shot destructive migrations are gated here so a
            // reinstall or second device can never re-run them against an
            // already-migrated database.
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS app_flags (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL,
                    updated_at TEXT
                );
            """)
            print("✅ app_flags table created")
        }

        migrator.registerMigration("create_inquiry_routing_corrections") { db in
            // Learned classification rules: manual kind corrections feed back
            // into the inquiry live-router prompt as worked examples.
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS inquiry_routing_corrections (
                    id TEXT PRIMARY KEY NOT NULL,
                    text TEXT NOT NULL,
                    from_kind TEXT NOT NULL,
                    to_kind TEXT NOT NULL,
                    deep_dive_uuid TEXT,
                    created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_inquiry_routing_corrections_recency
                    ON inquiry_routing_corrections(created_at DESC);
            """)
            print("✅ inquiry_routing_corrections table created")
        }

        migrator.registerMigration("add_canvas_blocks_metadata") { db in
            // Round-trip storage for block metadata (sticky color, rich body
            // document, etc.) — previously only note_content survived a restart.
            do {
                try db.execute(sql: "ALTER TABLE canvas_blocks ADD COLUMN metadata TEXT")
            } catch {
                // Column already exists on databases that pre-created it
            }
            print("✅ canvas_blocks.metadata column ensured")
        }

        migrator.registerMigration("canvas_drawings_sync_columns") { db in
            // Drawings sync to Supabase like canvas_blocks — the queue/resolver
            // machinery requires the standard version-tracking columns.
            for column in [
                "_local_version INTEGER NOT NULL DEFAULT 1",
                "_server_version INTEGER NOT NULL DEFAULT 0",
                "_sync_version INTEGER NOT NULL DEFAULT 0",
                "_local_pending INTEGER NOT NULL DEFAULT 0",
                "synced_at TEXT",
            ] {
                do {
                    try db.execute(sql: "ALTER TABLE canvas_drawings ADD COLUMN \(column)")
                } catch {
                    // Column already exists
                }
            }
            print("✅ canvas_drawings sync columns ensured")
        }

        migrator.registerMigration("inbox_sync_columns") { db in
            // The Inbox becomes a synced, local-first domain (July 2026): the
            // triage queue, capture lanes, and lane captures sync Mac ↔ iPhone
            // through the standard pipeline, which needs the version-tracking
            // columns plus snake created_at/updated_at (pull cursors, tombstone
            // comparisons, and ConflictResolver raw inserts read those).
            for table in ["inbox_items", "capture_destinations", "captured_items"] {
                for column in [
                    "is_deleted INTEGER NOT NULL DEFAULT 0",
                    "created_at TEXT",
                    "updated_at TEXT",
                    "synced_at TEXT",
                    "_local_version INTEGER NOT NULL DEFAULT 1",
                    "_server_version INTEGER NOT NULL DEFAULT 0",
                    "_sync_version INTEGER NOT NULL DEFAULT 0",
                    "_local_pending INTEGER NOT NULL DEFAULT 0",
                ] {
                    do {
                        try db.execute(sql: "ALTER TABLE \(table) ADD COLUMN \(column)")
                    } catch {
                        // Column already exists
                    }
                }
            }
            print("✅ inbox sync columns ensured")
        }

        migrator.registerMigration("create_deep_scout_taste") { db in
            // Learned source taste: Deep Scout import/dismiss decisions build
            // creator affinities that feed the query planner and ranker.
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS deep_scout_taste (
                    id TEXT PRIMARY KEY NOT NULL,
                    decision TEXT NOT NULL,
                    creator TEXT,
                    provider TEXT NOT NULL,
                    lane TEXT,
                    title TEXT NOT NULL,
                    deep_dive_uuid TEXT,
                    created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_deep_scout_taste_recency
                    ON deep_scout_taste(created_at DESC);
            """)
            print("✅ deep_scout_taste table created")
        }

        migrator.registerMigration("create_inquiry_gardener_decisions") { db in
            // The Gardener's memory: accepted/dismissed structure proposals
            // (promote / merge / graduate) so nothing is re-proposed.
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS inquiry_gardener_decisions (
                    id TEXT PRIMARY KEY NOT NULL,
                    proposal_key TEXT NOT NULL,
                    decision TEXT NOT NULL,
                    deep_dive_uuid TEXT,
                    created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_inquiry_gardener_decisions_topic
                    ON inquiry_gardener_decisions(deep_dive_uuid, created_at DESC);
            """)
            print("✅ inquiry_gardener_decisions table created")
        }

        migrator.registerMigration("media_attachments_sync_columns") { db in
            // Physical capture (July 2026): media_attachments becomes a synced
            // domain — photos of physical pages captured on either device flow
            // Mac ↔ iPhone through the standard pipeline. Owner generalization:
            // attachments link to any record kind (inbox_item, captured_item,
            // extract, source_atom), not just Telegram lane captures.
            for column in [
                "ownerType TEXT NOT NULL DEFAULT 'captured_item'",
                "ownerUUID TEXT NOT NULL DEFAULT ''",
                "is_deleted INTEGER NOT NULL DEFAULT 0",
                "created_at TEXT",
                "updated_at TEXT",
                "synced_at TEXT",
                "_local_version INTEGER NOT NULL DEFAULT 1",
                "_server_version INTEGER NOT NULL DEFAULT 0",
                "_sync_version INTEGER NOT NULL DEFAULT 0",
                "_local_pending INTEGER NOT NULL DEFAULT 0",
            ] {
                do {
                    try db.execute(sql: "ALTER TABLE media_attachments ADD COLUMN \(column)")
                } catch {
                    // Column already exists
                }
            }
            try db.execute(sql: """
                UPDATE media_attachments SET ownerUUID = capturedItemId WHERE ownerUUID = '';
                CREATE INDEX IF NOT EXISTS idx_media_attachments_owner
                    ON media_attachments(ownerType, ownerUUID);
            """)
            print("✅ media_attachments sync columns ensured")
        }

        migrator.registerMigration("create_capture_requests") { db in
            // The Mac → iPhone camera relay: this Mac writes pending scan
            // requests; the phone claims them and streams pages back.
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS capture_requests (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    uuid TEXT UNIQUE NOT NULL,
                    kind TEXT NOT NULL DEFAULT 'inbox_scan',
                    status TEXT NOT NULL DEFAULT 'pending',
                    scanSessionId TEXT NOT NULL DEFAULT '',
                    deepDiveUUID TEXT,
                    sessionUUID TEXT,
                    questionUUID TEXT,
                    questionTitle TEXT,
                    deepDiveTitle TEXT,
                    pageCount INTEGER NOT NULL DEFAULT 0,
                    requestedAt TEXT NOT NULL,
                    fulfilledAt TEXT,
                    is_deleted INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT,
                    updated_at TEXT,
                    synced_at TEXT,
                    _local_version INTEGER NOT NULL DEFAULT 1,
                    _server_version INTEGER NOT NULL DEFAULT 0,
                    _sync_version INTEGER NOT NULL DEFAULT 0,
                    _local_pending INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX IF NOT EXISTS idx_capture_requests_status
                    ON capture_requests(status, is_deleted);
            """)
            print("✅ capture_requests table created")
        }

        migrator.registerMigration("repair_canvas_blocks_orphaned_by_remote_tombstones") { db in
            // Remote atom tombstones (iOS/cloud deletes) historically soft-deleted
            // only the atom row — canvas placements survived and kept rendering
            // from their cached entity_title. The sync path now cascades; this
            // repairs rows orphaned before the fix.
            try db.execute(sql: """
                UPDATE canvas_blocks
                SET is_deleted = 1, updated_at = CURRENT_TIMESTAMP
                WHERE is_deleted = 0
                  AND entity_uuid IS NOT NULL AND entity_uuid != ''
                  AND entity_uuid IN (SELECT uuid FROM atoms WHERE is_deleted = 1)
            """)
            print("✅ Repaired canvas blocks orphaned by remote atom tombstones")
        }

        migrator.registerMigration("create_inbox_routing_corrections") { db in
            // Atlas routing correction ledger: every accept/dismiss/re-file of
            // an inbox suggestion becomes a worked example fed back into the
            // router prompt (the InquiryRoutingCorrectionStore pattern at
            // workspace scale).
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS inbox_routing_corrections (
                    id TEXT PRIMARY KEY NOT NULL,
                    text TEXT NOT NULL,
                    chosen_kind TEXT NOT NULL,
                    chosen_label TEXT NOT NULL,
                    rejected_kind TEXT,
                    rejected_label TEXT,
                    created_at TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_inbox_routing_corrections_recency
                    ON inbox_routing_corrections(created_at DESC);
            """)
            print("✅ inbox_routing_corrections table created")
        }

        migrator.registerMigration("create_agent_memory") { db in
            // Persistent agent memory: core facts (always injected into
            // prompts), per-conversation working memory, and embedding-
            // recalled archival memory. Previously in-RAM only — everything
            // the agent "remembered" vanished on restart.
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS agent_core_memory (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS agent_working_memory (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    conversation_id TEXT NOT NULL,
                    value TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_agent_working_memory_conversation
                    ON agent_working_memory(conversation_id);

                CREATE TABLE IF NOT EXISTS agent_archival_memory (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    uuid TEXT UNIQUE NOT NULL,
                    value TEXT NOT NULL,
                    embedding BLOB,
                    created_at TEXT NOT NULL
                );
            """)
            print("✅ agent memory tables created")
        }

        migrator.registerMigration("create_atom_revisions") { db in
            // Local-only version history: pre-image snapshots written by the
            // repository/sync write paths before content-changing overwrites.
            // Never synced, never searched. See AtomRevision.swift.
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS atom_revisions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    atom_uuid TEXT NOT NULL,
                    type TEXT NOT NULL,
                    title TEXT,
                    body TEXT,
                    structured TEXT,
                    metadata TEXT,
                    links TEXT,
                    local_version INTEGER NOT NULL DEFAULT 0,
                    source TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_atom_revisions_atom
                    ON atom_revisions(atom_uuid, created_at DESC);
            """)
            print("✅ atom_revisions table created")
        }

        migrator.registerMigration("create_recall_index") { db in
            // Recall semantic foundation: chunk vectors (normalized float
            // blobs, cosine = dot product) + a durable re-embed outbox.
            // Replaces the never-populated sqlite-vec tables. See AI/Recall/.
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS recall_vectors (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    entity_uuid TEXT NOT NULL,
                    entity_type TEXT NOT NULL,
                    chunk_index INTEGER NOT NULL DEFAULT 0,
                    doc_hash TEXT NOT NULL,
                    model TEXT NOT NULL,
                    page INTEGER,
                    text TEXT NOT NULL,
                    embedding BLOB NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_recall_vectors_entity
                    ON recall_vectors(entity_uuid);

                CREATE TABLE IF NOT EXISTS recall_outbox (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    entity_uuid TEXT UNIQUE NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    last_error TEXT,
                    created_at TEXT NOT NULL
                );
            """)
            print("✅ recall index tables created")
        }

        return migrator
    }

    nonisolated static func createContextIndexSchema(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS context_sources (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                title TEXT NOT NULL,
                atom_uuid TEXT,
                external_id TEXT,
                body_hash TEXT NOT NULL,
                metadata_hash TEXT NOT NULL,
                client_uuid TEXT,
                pin_state TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_context_sources_atom_uuid
                ON context_sources(atom_uuid);
            CREATE INDEX IF NOT EXISTS idx_context_sources_client_uuid
                ON context_sources(client_uuid);

            CREATE TABLE IF NOT EXISTS context_chunks (
                id TEXT PRIMARY KEY NOT NULL,
                source_id TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                raw_text TEXT NOT NULL,
                contextual_header TEXT NOT NULL,
                anchor TEXT,
                token_count INTEGER NOT NULL,
                body_hash TEXT NOT NULL,
                FOREIGN KEY(source_id) REFERENCES context_sources(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_context_chunks_source_id
                ON context_chunks(source_id, ordinal);

            CREATE VIRTUAL TABLE IF NOT EXISTS context_chunks_fts USING fts5(
                id UNINDEXED,
                source_id UNINDEXED,
                title,
                searchable_text,
                tokenize='porter unicode61 remove_diacritics 1'
            );
        """)
        try createContextSessionSchema(db)
    }

    nonisolated static func createContextSessionSchema(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS context_sessions (
                id TEXT PRIMARY KEY NOT NULL,
                surface TEXT NOT NULL,
                active_atom_uuid TEXT,
                active_client_uuid TEXT,
                recent_decision_summaries TEXT NOT NULL DEFAULT '[]',
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS context_session_sources (
                session_id TEXT NOT NULL,
                source_id TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                PRIMARY KEY (session_id, source_id),
                FOREIGN KEY(session_id) REFERENCES context_sessions(id) ON DELETE CASCADE,
                FOREIGN KEY(source_id) REFERENCES context_sources(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_context_session_sources_source_id
                ON context_session_sources(source_id);
        """)
    }

    // MARK: - Minimal Schema Creation
    // NOTE: Must be static to avoid @MainActor deadlock when called from GRDB migration closures
    private static func createMinimalSchema(_ db: Database) throws {
        // Create essential tables inline for standalone operation
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS ideas (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT,
                user_id TEXT,
                title TEXT,
                content TEXT NOT NULL,
                tags TEXT,
                project_id INTEGER,
                project_uuid TEXT,
                parent_id INTEGER,
                parent_uuid TEXT,
                connection_id INTEGER,
                connection_uuid TEXT,
                priority TEXT DEFAULT 'Medium',
                is_pinned INTEGER DEFAULT 0,
                pinned_at TEXT,
                metadata TEXT,
                focus_blocks TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                synced_at TEXT,
                is_deleted INTEGER DEFAULT 0,
                _local_version INTEGER DEFAULT 1,
                _server_version INTEGER DEFAULT 0,
                _sync_version INTEGER DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS content (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT,
                user_id TEXT,
                title TEXT NOT NULL,
                body TEXT,
                content_type TEXT,
                theme TEXT,
                tags TEXT,
                status TEXT DEFAULT 'draft',
                scheduled_at TEXT,
                last_opened_at TEXT,
                project_id INTEGER,
                project_uuid TEXT,
                metadata TEXT,
                focus_blocks TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                synced_at TEXT,
                is_deleted INTEGER DEFAULT 0,
                _local_version INTEGER DEFAULT 1,
                _server_version INTEGER DEFAULT 0,
                _sync_version INTEGER DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT,
                user_id TEXT,
                title TEXT NOT NULL,
                status TEXT DEFAULT 'todo',
                priority TEXT DEFAULT 'medium',
                start_time TEXT,
                end_time TEXT,
                duration_minutes INTEGER,
                due_date TEXT,
                focus_date TEXT,
                project_id INTEGER,
                project_uuid TEXT,
                origin_idea_id INTEGER,
                origin_idea_uuid TEXT,
                description TEXT,
                checklist TEXT,
                recurrence TEXT,
                is_unscheduled INTEGER DEFAULT 0,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                synced_at TEXT,
                is_deleted INTEGER DEFAULT 0,
                _local_version INTEGER DEFAULT 1,
                _server_version INTEGER DEFAULT 0,
                _sync_version INTEGER DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS projects (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT,
                user_id TEXT,
                title TEXT NOT NULL,
                description TEXT,
                color TEXT DEFAULT '#8B5CF6',
                tags TEXT,
                priority TEXT DEFAULT 'Medium',
                status TEXT DEFAULT 'active',
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                synced_at TEXT,
                is_deleted INTEGER DEFAULT 0,
                _local_version INTEGER DEFAULT 1,
                _server_version INTEGER DEFAULT 0,
                _sync_version INTEGER DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS research (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT,
                user_id TEXT,
                title TEXT NOT NULL,
                url TEXT,
                content TEXT,
                summary TEXT,
                research_type TEXT,
                processing_status TEXT DEFAULT 'new',
                thumbnail_url TEXT,
                query TEXT,
                findings TEXT,
                auto_metadata TEXT,
                tags TEXT,
                project_id INTEGER,
                project_uuid TEXT,
                metadata TEXT,
                focus_blocks TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                synced_at TEXT,
                is_deleted INTEGER DEFAULT 0,
                _local_version INTEGER DEFAULT 1,
                _server_version INTEGER DEFAULT 0,
                _sync_version INTEGER DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS calendar_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT,
                user_id TEXT,
                title TEXT NOT NULL,
                description TEXT,
                start_time TEXT NOT NULL,
                end_time TEXT NOT NULL,
                is_all_day INTEGER DEFAULT 0,
                location TEXT,
                color TEXT,
                project_id INTEGER,
                project_uuid TEXT,
                recurrence TEXT,
                reminder_minutes INTEGER,
                linked_entities TEXT,
                calendar_type TEXT DEFAULT 'event',
                is_completed INTEGER DEFAULT 0,
                completed_at TEXT,
                is_unscheduled INTEGER DEFAULT 0,
                reminder_due_at TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                synced_at TEXT,
                is_deleted INTEGER DEFAULT 0,
                _local_version INTEGER DEFAULT 1,
                _server_version INTEGER DEFAULT 0,
                _sync_version INTEGER DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS journal_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT,
                user_id TEXT,
                content TEXT NOT NULL,
                source TEXT DEFAULT 'cosmo-ai',
                status TEXT DEFAULT 'pending',
                ai_response TEXT,
                linked_tasks TEXT,
                linked_ideas TEXT,
                linked_content TEXT,
                error_message TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                synced_at TEXT,
                is_deleted INTEGER DEFAULT 0,
                _local_version INTEGER DEFAULT 1,
                _server_version INTEGER DEFAULT 0,
                _sync_version INTEGER DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS cosmo_notifications (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                notification_id TEXT NOT NULL,
                type TEXT NOT NULL,
                title TEXT NOT NULL,
                message TEXT,
                entity_type TEXT,
                entity_id TEXT,
                scheduled_for TEXT NOT NULL,
                action_taken TEXT,
                dismissed_at TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS connections (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT,
                user_id TEXT,
                title TEXT NOT NULL,
                project_id INTEGER,
                project_uuid TEXT,
                metadata TEXT,
                idea TEXT,
                personal_belief TEXT,
                goal TEXT,
                problems TEXT,
                benefit TEXT,
                beliefs_objections TEXT,
                example TEXT,
                process TEXT,
                notes TEXT,
                references_data TEXT,
                source_text TEXT,
                extraction_confidence REAL,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                synced_at TEXT,
                is_deleted INTEGER DEFAULT 0,
                _local_version INTEGER DEFAULT 1,
                _server_version INTEGER DEFAULT 0,
                _sync_version INTEGER DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS semantic_chunks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                entity_type TEXT NOT NULL,
                entity_id INTEGER NOT NULL,
                field_name TEXT,
                chunk_index INTEGER DEFAULT 0,
                text TEXT,
                text_hash TEXT,
                vector BLOB,
                start_time REAL,
                end_time REAL,
                model_version TEXT DEFAULT 'local',
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(entity_type, entity_id, field_name, chunk_index)
            );

            CREATE TABLE IF NOT EXISTS canvas_blocks (
                id TEXT PRIMARY KEY,
                uuid TEXT,
                user_id TEXT,
                document_type TEXT NOT NULL,
                document_id INTEGER NOT NULL,
                document_uuid TEXT,
                entity_id INTEGER NOT NULL,
                entity_uuid TEXT,
                entity_type TEXT NOT NULL,
                entity_title TEXT,
                position_x INTEGER NOT NULL,
                position_y INTEGER NOT NULL,
                width INTEGER,
                height INTEGER,
                is_collapsed INTEGER DEFAULT 0,
                zone TEXT,
                note_content TEXT,
                z_index INTEGER DEFAULT 0,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
                synced_at TEXT,
                is_deleted INTEGER DEFAULT 0,
                _local_version INTEGER DEFAULT 1,
                _server_version INTEGER DEFAULT 0,
                _sync_version INTEGER DEFAULT 0,
                _local_pending INTEGER DEFAULT 0,
                thinkspace_id TEXT,
                is_pinned INTEGER DEFAULT 0,
                atom_uuid TEXT
            );

            CREATE TABLE IF NOT EXISTS sync_queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT NOT NULL,
                table_name TEXT NOT NULL,
                row_id INTEGER,
                operation TEXT NOT NULL,
                data TEXT,
                local_version INTEGER DEFAULT 0,
                created_at INTEGER DEFAULT (cast(strftime('%s','now') * 1000 as integer)),
                status TEXT DEFAULT 'pending',
                retry_count INTEGER DEFAULT 0,
                error_message TEXT,
                synced_at TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_ideas_uuid ON ideas(uuid);
            CREATE INDEX IF NOT EXISTS idx_content_uuid ON content(uuid);
            CREATE INDEX IF NOT EXISTS idx_tasks_uuid ON tasks(uuid);
            CREATE INDEX IF NOT EXISTS idx_projects_uuid ON projects(uuid);
            CREATE INDEX IF NOT EXISTS idx_research_uuid ON research(uuid);
            CREATE INDEX IF NOT EXISTS idx_calendar_events_uuid ON calendar_events(uuid);
            CREATE INDEX IF NOT EXISTS idx_journal_entries_uuid ON journal_entries(uuid);
            CREATE INDEX IF NOT EXISTS idx_connections_uuid ON connections(uuid);
            CREATE INDEX IF NOT EXISTS idx_canvas_blocks_document ON canvas_blocks(document_type, document_id, is_deleted);
            CREATE INDEX IF NOT EXISTS idx_canvas_blocks_thinkspace_lookup ON canvas_blocks(thinkspace_id, is_deleted, z_index);
            CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status, created_at);
        """)
    }

    // MARK: - Database Access
    func read<T>(_ block: (Database) throws -> T) throws -> T {
        return try dbQueue.read(block)
    }

    func write<T>(_ block: (Database) throws -> T) throws -> T {
        return try dbQueue.write(block)
    }

    func asyncRead<T>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        return try await dbQueue.read(block)
    }

    func asyncWrite<T>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        return try await dbQueue.write(block)
    }

    // MARK: - Observation
    func observe<T>(
        _ observation: @escaping (Database) throws -> T
    ) -> DatabasePublishers.Value<T> {
        return ValueObservation.tracking(observation)
            .publisher(in: dbQueue)
    }
}
