import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:intl/intl.dart';

import '../../models/contact.dart';
import '../../models/interaction.dart';
import '../../models/prayer_request.dart';
import 'embedding_service.dart';

/// Source kind for an indexed document. Drives the snippet rendering and the
/// "from a coffee chat" / "from a prayer request" provenance label.
enum IndexDocumentType { interaction, prayerRequest }

/// One unit indexed in the semantic search store. Pure value type; constructed
/// by [documentsFor] so callers can unit-test indexing logic without booting
/// the real embedder.
class IndexDocument {
  IndexDocument({
    required this.id,
    required this.content,
    required this.contactId,
    required this.type,
  });

  /// Stable id used as the vector-store primary key. Composed as
  /// `<type>:<syncId>` so interaction / prayer ids never collide.
  final String id;

  /// Text fed to the embedder. Should already be trimmed and non-empty.
  final String content;

  /// Owning contact's `id`, used to look the contact up when assembling
  /// [SemanticMatch] results.
  final String contactId;

  final IndexDocumentType type;

  Map<String, dynamic> toMetadata() => {
        'contactId': contactId,
        'type': type.name,
      };

  static IndexDocumentType? typeFromMetadata(String? metadata) {
    if (metadata == null) return null;
    try {
      final value = (jsonDecode(metadata) as Map)['type'] as String?;
      return IndexDocumentType.values.firstWhere(
        (t) => t.name == value,
        orElse: () => IndexDocumentType.interaction,
      );
    } catch (_) {
      return null;
    }
  }

  static String? contactIdFromMetadata(String? metadata) {
    if (metadata == null) return null;
    try {
      return (jsonDecode(metadata) as Map)['contactId'] as String?;
    } catch (_) {
      return null;
    }
  }
}

/// One ranked semantic search result with enough provenance to render a
/// "from X" subtitle in the UI.
class SemanticMatch {
  SemanticMatch({
    required this.contact,
    required this.type,
    required this.snippet,
    required this.score,
  });

  final Contact contact;
  final IndexDocumentType type;
  final String snippet;
  final double score;
}

/// Pure: turn a snapshot of contacts into the set of documents to embed.
/// Soft-deleted contacts and soft-deleted sub-items are excluded. Documents
/// with empty content (no summary, notes, etc.) are dropped so we don't
/// embed pure whitespace.
List<IndexDocument> documentsFor(List<Contact> contacts) {
  final formatter = DateFormat.yMMMd();
  final out = <IndexDocument>[];

  for (final contact in contacts) {
    if (contact.deletedAt != null) continue;
    for (final interaction in contact.interactions) {
      if (interaction.deletedAt != null) continue;
      final content = _interactionContent(interaction, formatter);
      if (content.isEmpty) continue;
      out.add(
        IndexDocument(
          id: 'interaction:${interaction.syncId}',
          content: content,
          contactId: contact.id,
          type: IndexDocumentType.interaction,
        ),
      );
    }
    for (final prayer in contact.prayerRequests) {
      if (prayer.deletedAt != null) continue;
      final content = _prayerContent(prayer);
      if (content.isEmpty) continue;
      out.add(
        IndexDocument(
          id: 'prayer:${prayer.syncId}',
          content: content,
          contactId: contact.id,
          type: IndexDocumentType.prayerRequest,
        ),
      );
    }
  }
  return out;
}

String _interactionContent(Interaction interaction, DateFormat formatter) {
  // The date alone isn't a searchable signal — require at least one of
  // summary / notes / location to be non-empty before we emit a document.
  final hasMeaningfulText = interaction.summary.trim().isNotEmpty ||
      (interaction.notes?.trim().isNotEmpty ?? false) ||
      (interaction.location?.trim().isNotEmpty ?? false);
  if (!hasMeaningfulText) return '';

  final parts = <String>[
    formatter.format(interaction.occurredAt),
    interaction.summary,
    if (interaction.location != null && interaction.location!.isNotEmpty)
      interaction.location!,
    if (interaction.notes != null && interaction.notes!.isNotEmpty)
      interaction.notes!,
  ];
  return parts.where((p) => p.trim().isNotEmpty).join(' | ').trim();
}

String _prayerContent(PrayerRequest prayer) {
  final parts = <String>[
    prayer.description,
    if (prayer.category != null && prayer.category!.isNotEmpty)
      prayer.category!,
    if (prayer.reflectionNotes != null && prayer.reflectionNotes!.isNotEmpty)
      prayer.reflectionNotes!,
  ];
  return parts.where((p) => p.trim().isNotEmpty).join(' | ').trim();
}

/// Status of the in-process semantic index.
enum SemanticIndexStatus {
  notInitialized,
  initializing,
  indexing,
  ready,
  error,
}

/// High-level semantic search facade.
///
/// Wraps an [EmbeddingService] (to score the query) and a persistent vector
/// store (to hold the index of every interaction + prayer request). Designed
/// so a test can drop in fakes of both halves.
abstract class SemanticSearchService {
  SemanticIndexStatus get status;

  /// Most recent error (if [status] is [SemanticIndexStatus.error]).
  Object? get lastError;

  /// Initializes the vector store. Idempotent; safe to call on every app
  /// start as long as [dbPath] is stable.
  Future<void> initialize(String dbPath);

  /// Rebuilds the index from a fresh snapshot of contacts. Existing
  /// documents are cleared first, so this is safe to call after CRUD even
  /// when an item is deleted.
  Future<void> rebuildIndex(
    List<Contact> contacts, {
    void Function(int done, int total)? onProgress,
  });

  /// Runs a semantic query and returns up to [topK] matches.
  Future<List<SemanticMatch>> query(
    String text, {
    required Map<String, Contact> contactsById,
    int topK = 10,
  });

  /// Clears all documents from the vector store. Used on import / data wipe.
  Future<void> clear();

  /// Number of documents currently in the persistent index. Used by callers
  /// to skip a wholesale rebuild when the prior session's index is intact.
  Future<int> documentCount();

  /// Releases the underlying vector-store DB handle. Safe to call when
  /// uninitialized. Intended for app-teardown to silence Android's
  /// `CloseGuard` `flutter_gemma_vectors.db was leaked` warning.
  Future<void> close();
}

/// Production impl wiring [FlutterGemmaEmbeddingService] to flutter_gemma's
/// built-in vector store (HNSW). The vector store auto-embeds documents
/// using the embedder set as "active" by [EmbeddingService.load].
class FlutterGemmaSemanticSearchService implements SemanticSearchService {
  FlutterGemmaSemanticSearchService(this._embedding);

  final EmbeddingService _embedding;
  bool _vectorStoreReady = false;
  SemanticIndexStatus _status = SemanticIndexStatus.notInitialized;
  Object? _lastError;

  @override
  SemanticIndexStatus get status => _status;

  @override
  Object? get lastError => _lastError;

  @override
  Future<void> initialize(String dbPath) async {
    if (_vectorStoreReady) return;
    _status = SemanticIndexStatus.initializing;
    _lastError = null;
    try {
      if (!_embedding.isReady) {
        throw StateError(
          'Embedder must be loaded before initializing the vector store.',
        );
      }
      await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);
      _vectorStoreReady = true;
      _status = SemanticIndexStatus.ready;
    } catch (e) {
      _lastError = e;
      _status = SemanticIndexStatus.error;
      rethrow;
    }
  }

  @override
  Future<void> rebuildIndex(
    List<Contact> contacts, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (!_vectorStoreReady) {
      throw StateError('rebuildIndex called before initialize()');
    }
    _status = SemanticIndexStatus.indexing;
    _lastError = null;
    try {
      await FlutterGemmaPlugin.instance.clearVectorStore();
      final docs = documentsFor(contacts);
      var done = 0;

      // Process documents in batches using Future.wait to overlap platform channel
      // IPC calls. This dramatically reduces total indexing time while still
      // yielding to the UI thread between batches to prevent renderer starvation.
      const batchSize = 10;
      for (var i = 0; i < docs.length; i += batchSize) {
        final end = (i + batchSize < docs.length) ? i + batchSize : docs.length;
        final batch = docs.sublist(i, end);

        final futures = <Future<void>>[];
        for (final doc in batch) {
          futures.add(
            FlutterGemmaPlugin.instance
                .addDocument(
              id: doc.id,
              content: doc.content,
              metadata: jsonEncode(doc.toMetadata()),
            )
                .then((_) {
              done += 1;
              onProgress?.call(done, docs.length);
            }),
          );
        }
        await Future.wait(futures);
        await Future<void>.delayed(Duration.zero);
      }
      _status = SemanticIndexStatus.ready;
    } catch (e) {
      _lastError = e;
      _status = SemanticIndexStatus.error;
      rethrow;
    }
  }

  @override
  Future<List<SemanticMatch>> query(
    String text, {
    required Map<String, Contact> contactsById,
    int topK = 10,
  }) async {
    if (!_vectorStoreReady) {
      throw StateError('query called before initialize()');
    }
    final results = await FlutterGemmaPlugin.instance.searchSimilar(
      query: text,
      topK: topK,
    );
    return resultsToMatches(results, contactsById);
  }

  @override
  Future<void> clear() async {
    if (!_vectorStoreReady) return;
    await FlutterGemmaPlugin.instance.clearVectorStore();
  }

  @override
  Future<int> documentCount() async {
    if (!_vectorStoreReady) return 0;
    try {
      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      return stats.documentCount;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> close() async {
    if (!_vectorStoreReady) return;
    try {
      // FlutterGemmaPlugin's high-level interface doesn't surface
      // closeVectorStore, but the underlying pigeon channel does (it's
      // what the plugin's own MobileVectorStoreRepository.close() calls).
      // Hitting it directly keeps Android's CloseGuard from logging
      // `flutter_gemma_vectors.db was leaked` at process teardown.
      await PlatformService().closeVectorStore();
    } finally {
      _vectorStoreReady = false;
      _status = SemanticIndexStatus.notInitialized;
    }
  }
}

/// Pure: map vector-store retrieval results back to UI-facing matches by
/// joining on `contactId` from each result's metadata. Results referencing
/// missing contacts are silently dropped (which can happen if a contact was
/// deleted after the index was built but before [rebuildIndex] re-ran).
List<SemanticMatch> resultsToMatches(
  List<RetrievalResult> results,
  Map<String, Contact> contactsById,
) {
  final matches = <SemanticMatch>[];
  for (final r in results) {
    final contactId = IndexDocument.contactIdFromMetadata(r.metadata);
    if (contactId == null) continue;
    final contact = contactsById[contactId];
    if (contact == null) continue;
    final type = IndexDocument.typeFromMetadata(r.metadata) ??
        IndexDocumentType.interaction;
    matches.add(
      SemanticMatch(
        contact: contact,
        type: type,
        snippet: r.content,
        score: r.similarity,
      ),
    );
  }
  return matches;
}
