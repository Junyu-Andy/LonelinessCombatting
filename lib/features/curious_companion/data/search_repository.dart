/// Client-side wrapper over the `webSearch` Cloud Function (Dev Req §6.1).
///
/// The Cloud Function is responsible for the API key, rate limit, and
/// safety filter. The client only needs to ship the query + decide
/// what to do with the returned list.
library;

import 'package:cloud_functions/cloud_functions.dart';

class SearchResult {
  final String title;
  final String snippet;
  final String link;

  const SearchResult({
    required this.title,
    required this.snippet,
    required this.link,
  });
}

class SearchResponse {
  final List<SearchResult> results;

  /// True when the cloud function reports it is not yet configured
  /// (SEARCH_API_KEY / SEARCH_CX secrets not set). The UI uses this
  /// to fall back to "I'm not sure — want to look together?" copy.
  final bool unavailable;

  const SearchResponse({
    required this.results,
    required this.unavailable,
  });
}

class SearchRepository {
  SearchRepository({required this.available});

  /// False when Firebase isn't configured — search is impossible.
  final bool available;

  Future<SearchResponse> search(String query) async {
    if (!available || query.trim().isEmpty) {
      return const SearchResponse(results: [], unavailable: true);
    }
    try {
      final result = await FirebaseFunctions
          .instanceFor(region: 'asia-east2')
          .httpsCallable('webSearch')
          .call(<String, dynamic>{'query': query})
          .timeout(const Duration(seconds: 15));
      final data = result.data;
      if (data is! Map) {
        return const SearchResponse(results: [], unavailable: true);
      }
      final unavailable = (data['unavailable'] as bool?) ?? false;
      final rawResults = data['results'];
      final out = <SearchResult>[];
      if (rawResults is List) {
        for (final r in rawResults) {
          if (r is Map) {
            out.add(SearchResult(
              title: (r['title'] as String?) ?? '',
              snippet: (r['snippet'] as String?) ?? '',
              link: (r['link'] as String?) ?? '',
            ));
          }
        }
      }
      return SearchResponse(results: out, unavailable: unavailable);
    } on FirebaseFunctionsException {
      return const SearchResponse(results: [], unavailable: true);
    } catch (_) {
      return const SearchResponse(results: [], unavailable: true);
    }
  }
}
