import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

// ──────────────────────────────────────────────────────────────────────────────
// TokenizerService
//
// Supports two tokenizer formats detected at load time:
//   • WordPiece  — loaded from a vocab.txt file (BERT-style)
//   • BPE        — loaded from a tokenizer.json file (HuggingFace format)
//
// Usage:
//   final tok = await TokenizerService.load(vocabPath: 'assets/vocab.txt');
//   final ids  = tok.encode('Hello world', maxLength: 128);
//   final text = tok.decode(ids);
// ──────────────────────────────────────────────────────────────────────────────

enum _TokenizerType { wordPiece, bpe }

class TokenizerService {
  final _TokenizerType _type;

  // token → id
  final Map<String, int> _vocab;
  // id → token
  final Map<int, String> _idToToken;
  // merge pair → priority index (lower = higher priority)
  final Map<String, int> _mergeRank;
  // Whether the BPE pre-tokenizer is ByteLevel (GPT-2 style)
  final bool _byteLevel;
  // BPE post-processor special tokens: [[single_template_parts], [pair_template_parts]]
  // Each part is either a special token string (if starts with special marker) or a sequence placeholder
  final List<String> _bosTokens;  // prepended to sequence
  final List<String> _eosTokens;  // appended to sequence

  // Special token IDs
  final int padId;
  final int unkId;
  final int clsId;  // [CLS] for BERT, <s> for RoBERTa
  final int sepId;  // [SEP] for BERT, </s> for RoBERTa
  final int bosId;  // beginning of sequence
  final int eosId;  // end of sequence / eos

  // Byte-level encoding table (GPT-2 style: maps byte 0-255 → unicode char)
  static final Map<int, String> _byteToUnicode = _buildByteToUnicode();
  static final Map<String, int> _unicodeToByte = {
    for (final e in _buildByteToUnicode().entries) e.value: e.key,
  };

  TokenizerService._({
    required _TokenizerType type,
    required Map<String, int> vocab,
    required List<(String, String)> merges,
    required bool byteLevel,
    required List<String> bosTokens,
    required List<String> eosTokens,
    required this.padId,
    required this.unkId,
    required this.clsId,
    required this.sepId,
    required this.bosId,
    required this.eosId,
  })  : _type = type,
        _vocab = vocab,
        _idToToken = {for (final e in vocab.entries) e.value: e.key},
        _mergeRank = {
          for (int i = 0; i < merges.length; i++)
            '${merges[i].$1}\u0000${merges[i].$2}': i,
        },
        _byteLevel = byteLevel,
        _bosTokens = bosTokens,
        _eosTokens = eosTokens;

  // ────────────────────────────────────────────────────────────────────────────
  // Factory: auto-detects format, priority = tokenizer.json > vocab.txt
  // ────────────────────────────────────────────────────────────────────────────
  static Future<TokenizerService?> load({
    String? vocabPath,
    String? tokenizerJsonPath,
    bool isLocalFile = false,
    String? localDir,
  }) async {
    // For local (downloaded) models, the downloaded files are named by asset key:
    //   localDir/tokenizer  → tokenizer.json content
    //   localDir/vocab      → vocab.txt content
    if (isLocalFile && localDir != null) {
      final tokFile = File('$localDir/tokenizer');
      if (await tokFile.exists()) {
        try {
          final json = jsonDecode(await tokFile.readAsString()) as Map<String, dynamic>;
          return _fromTokenizerJson(json);
        } catch (e) {
          debugPrint('[Tokenizer] Failed to parse localDir/tokenizer as JSON: $e');
        }
      }
      final vocabFile = File('$localDir/vocab');
      if (await vocabFile.exists()) {
        try {
          return _fromVocabTxt(await vocabFile.readAsString());
        } catch (e) {
          debugPrint('[Tokenizer] Failed to parse localDir/vocab: $e');
        }
      }
      debugPrint('[Tokenizer] No tokenizer or vocab file found in $localDir');
      return null;
    }

    // Bundled asset paths
    if (tokenizerJsonPath != null) {
      try {
        final content = await rootBundle.loadString(tokenizerJsonPath);
        final json = jsonDecode(content) as Map<String, dynamic>;
        return _fromTokenizerJson(json);
      } catch (e) {
        debugPrint('[Tokenizer] Failed to load tokenizer.json from $tokenizerJsonPath: $e');
      }
    }
    if (vocabPath != null) {
      try {
        final content = await rootBundle.loadString(vocabPath);
        return _fromVocabTxt(content);
      } catch (e) {
        debugPrint('[Tokenizer] Failed to load vocab.txt from $vocabPath: $e');
      }
    }

    debugPrint('[Tokenizer] No tokenizer source available.');
    return null;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Parse from HuggingFace tokenizer.json (BPE)
  // ────────────────────────────────────────────────────────────────────────────
  static TokenizerService _fromTokenizerJson(Map<String, dynamic> json) {
    final model = json['model'] as Map<String, dynamic>? ?? {};
    final rawVocab = (model['vocab'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, (v as num).toInt()));
    final rawMerges = (model['merges'] as List<dynamic>? ?? [])
        .map((m) {
          final parts = (m as String).split(' ');
          return (parts[0], parts.length > 1 ? parts[1] : '');
        })
        .toList();

    // Collect special tokens from added_tokens
    final addedTokens = (json['added_tokens'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final specialById = <int, String>{};
    for (final t in addedTokens) {
      if (t['special'] == true) {
        specialById[(t['id'] as num).toInt()] = t['content'] as String;
      }
    }

    // Detect ByteLevel pre-tokenizer
    final preTokenizer = json['pre_tokenizer'] as Map<String, dynamic>?;
    final bool byteLevel =
        preTokenizer != null && (preTokenizer['type'] as String?) == 'ByteLevel';

    // Detect BOS/EOS from post-processor
    final postProc = json['post_processor'] as Map<String, dynamic>?;
    List<String> bosTokens = [];
    List<String> eosTokens = [];
    if (postProc != null) {
      final single = postProc['single'] as List<dynamic>?;
      if (single != null) {
        for (final part in single) {
          final p = part as Map<String, dynamic>;
          if (p.containsKey('SpecialToken')) {
            final id = p['SpecialToken']['id'] as String;
            // If it appears before $A it's BOS, after it's EOS — simplified detection
            if (bosTokens.isEmpty) {
              bosTokens.add(id);
            } else {
              eosTokens.add(id);
            }
          }
        }
      }
    }

    // Resolve special token IDs (try common names).
    // EOS is resolved first so it can serve as the pad fallback for models like
    // GPT-2 that have no dedicated <pad> token (standard HuggingFace practice).
    int unkId = _findId(rawVocab, const ['<unk>', '[UNK]'], 0);
    int bosId = _findId(rawVocab, const ['<s>', '<bos>', '[CLS]', '<|startoftext|>'], 1);
    int eosId = _findId(rawVocab, const ['</s>', '<eos>', '<|endoftext|>', '[SEP]'], 2);
    int clsId = _findId(rawVocab, const ['[CLS]', '<s>'], bosId);
    int sepId = _findId(rawVocab, const ['[SEP]', '</s>'], eosId);
    // Fall back to eosId when no dedicated pad token exists (e.g. GPT-2 uses 50256 for both).
    int padId = _findId(rawVocab, const ['<pad>', '[PAD]', '<|padding|>'], eosId);

    debugPrint('[Tokenizer] Loaded BPE tokenizer: ${rawVocab.length} tokens, ${rawMerges.length} merges, byteLevel=$byteLevel');

    return TokenizerService._(
      type: _TokenizerType.bpe,
      vocab: rawVocab,
      merges: rawMerges,
      byteLevel: byteLevel,
      bosTokens: bosTokens,
      eosTokens: eosTokens,
      padId: padId,
      unkId: unkId,
      clsId: clsId,
      sepId: sepId,
      bosId: bosId,
      eosId: eosId,
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Parse from vocab.txt (WordPiece)
  // ────────────────────────────────────────────────────────────────────────────
  static TokenizerService _fromVocabTxt(String content) {
    final lines = content.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final vocab = <String, int>{};
    for (int i = 0; i < lines.length; i++) {
      vocab[lines[i]] = i;
    }

    int padId = _findId(vocab, const ['[PAD]', '<pad>'], 0);
    int unkId = _findId(vocab, const ['[UNK]', '<unk>'], 100);
    int clsId = _findId(vocab, const ['[CLS]', '<s>'], 101);
    int sepId = _findId(vocab, const ['[SEP]', '</s>'], 102);

    debugPrint('[Tokenizer] Loaded WordPiece tokenizer: ${vocab.length} tokens');

    return TokenizerService._(
      type: _TokenizerType.wordPiece,
      vocab: vocab,
      merges: [],
      byteLevel: false,
      bosTokens: [],
      eosTokens: [],
      padId: padId,
      unkId: unkId,
      clsId: clsId,
      sepId: sepId,
      bosId: clsId,
      eosId: sepId,
    );
  }

  static int _findId(Map<String, int> vocab, List<String> candidates, int fallback) {
    for (final name in candidates) {
      if (vocab.containsKey(name)) return vocab[name]!;
    }
    return fallback;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // encode — text → List<int> token IDs
  // ────────────────────────────────────────────────────────────────────────────
  List<int> encode(
    String text, {
    int maxLength = 512,
    bool padding = true,
    bool truncation = true,
    bool addSpecialTokens = true,
  }) {
    final List<int> ids = _type == _TokenizerType.wordPiece
        ? _wordPieceEncode(text)
        : _bpeEncode(text);

    // Add special tokens
    List<int> result = [...ids];
    if (addSpecialTokens) {
      if (_type == _TokenizerType.wordPiece) {
        result = [clsId, ...result, sepId];
      } else {
        // BPE: prepend BOS tokens, append EOS tokens from post-processor
        final bosIds = _bosTokens.map((t) => _vocab[t] ?? bosId).toList();
        final eosIds = _eosTokens.map((t) => _vocab[t] ?? eosId).toList();
        result = [...bosIds, ...result, ...eosIds];
      }
    }

    // Truncate
    if (truncation && result.length > maxLength) {
      // Preserve EOS at end if we added it
      if (addSpecialTokens && result.last == (_type == _TokenizerType.wordPiece ? sepId : eosId)) {
        result = [...result.sublist(0, maxLength - 1), result.last];
      } else {
        result = result.sublist(0, maxLength);
      }
    }

    // Pad
    if (padding && result.length < maxLength) {
      result = [...result, ...List.filled(maxLength - result.length, padId)];
    }

    return result;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // decode — List<int> token IDs → String
  // ────────────────────────────────────────────────────────────────────────────
  String decode(List<int> tokenIds, {bool skipSpecialTokens = true}) {
    final specialIds = {padId, unkId, clsId, sepId, bosId, eosId};

    final tokens = <String>[];
    for (final id in tokenIds) {
      if (skipSpecialTokens && specialIds.contains(id)) continue;
      final token = _idToToken[id];
      if (token == null) continue;
      tokens.add(token);
    }

    if (_type == _TokenizerType.wordPiece) {
      return _wordPieceDecode(tokens);
    } else {
      return _bpeDecode(tokens);
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // WordPiece implementation
  // ────────────────────────────────────────────────────────────────────────────

  List<int> _wordPieceEncode(String text) {
    final words = _wordPiecePreTokenize(text.toLowerCase());
    final ids = <int>[];
    for (final word in words) {
      ids.addAll(_wordPieceTokenizeWord(word));
    }
    return ids;
  }

  List<String> _wordPiecePreTokenize(String text) {
    // Split on whitespace, then split off punctuation
    final words = <String>[];
    for (final raw in text.split(RegExp(r'\s+'))) {
      if (raw.isEmpty) continue;
      // Split punctuation off as separate tokens
      final buffer = StringBuffer();
      for (final char in raw.runes.map(String.fromCharCode)) {
        if (_isPunctuation(char)) {
          if (buffer.isNotEmpty) {
            words.add(buffer.toString());
            buffer.clear();
          }
          words.add(char);
        } else {
          buffer.write(char);
        }
      }
      if (buffer.isNotEmpty) words.add(buffer.toString());
    }
    return words;
  }

  bool _isPunctuation(String char) {
    final cp = char.codeUnitAt(0);
    if ((cp >= 33 && cp <= 47) ||
        (cp >= 58 && cp <= 64) ||
        (cp >= 91 && cp <= 96) ||
        (cp >= 123 && cp <= 126)) {
      return true;
    }
    return false;
  }

  List<int> _wordPieceTokenizeWord(String word) {
    if (word.length > 200) return [unkId];
    final ids = <int>[];
    int start = 0;
    bool isBad = false;
    while (start < word.length) {
      int end = word.length;
      String? curSubstr;
      while (start < end) {
        final substr = (start == 0 ? '' : '##') + word.substring(start, end);
        if (_vocab.containsKey(substr)) {
          curSubstr = substr;
          break;
        }
        end--;
      }
      if (curSubstr == null) {
        isBad = true;
        break;
      }
      ids.add(_vocab[curSubstr]!);
      start = end;
    }
    return isBad ? [unkId] : ids;
  }

  String _wordPieceDecode(List<String> tokens) {
    final buffer = StringBuffer();
    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.startsWith('##')) {
        buffer.write(token.substring(2));
      } else {
        if (i > 0) buffer.write(' ');
        buffer.write(token);
      }
    }
    return buffer.toString().trim();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // BPE implementation
  // ────────────────────────────────────────────────────────────────────────────

  List<int> _bpeEncode(String text) {
    // Pre-tokenize
    final words = _byteLevel ? _byteLevelPreTokenize(text) : text.split(RegExp(r'\s+'));
    final ids = <int>[];
    for (final word in words) {
      if (word.isEmpty) continue;
      ids.addAll(_bpeTokenizeWord(word));
    }
    return ids;
  }

  List<String> _byteLevelPreTokenize(String text) {
    // GPT-2 style: split on whitespace, prefix non-initial words with Ġ (U+0120)
    final rawWords = text.split(RegExp(r'(?=\s)'));
    final result = <String>[];
    for (final w in rawWords) {
      if (w.isEmpty) continue;
      // Encode each byte via the byte-to-unicode map
      final encoded = w.runes
          .expand((cp) => utf8.encode(String.fromCharCode(cp)))
          .map((b) => _byteToUnicode[b] ?? String.fromCharCode(b))
          .join();
      result.add(encoded);
    }
    return result;
  }

  List<int> _bpeTokenizeWord(String word) {
    if (_vocab.containsKey(word)) return [_vocab[word]!];

    // Start with individual characters (or byte-encoded chars)
    List<String> symbols = word.split('');

    // Apply BPE merges greedily by rank
    while (symbols.length > 1) {
      int bestRank = 0x7fffffff;
      int bestIdx = -1;
      for (int i = 0; i < symbols.length - 1; i++) {
        final key = '${symbols[i]}\u0000${symbols[i + 1]}';
        final rank = _mergeRank[key];
        if (rank != null && rank < bestRank) {
          bestRank = rank;
          bestIdx = i;
        }
      }
      if (bestIdx == -1) break; // no more merges possible

      final merged = symbols[bestIdx] + symbols[bestIdx + 1];
      symbols = [
        ...symbols.sublist(0, bestIdx),
        merged,
        ...symbols.sublist(bestIdx + 2),
      ];
    }

    return symbols.map((s) => _vocab[s] ?? unkId).toList();
  }

  String _bpeDecode(List<String> tokens) {
    final joined = tokens.join('');
    if (_byteLevel) {
      // Convert byte-level unicode back to UTF-8 bytes, then decode
      try {
        final bytes = joined.runes
            .expand((cp) {
              final char = String.fromCharCode(cp);
              final byte = _unicodeToByte[char];
              return byte != null ? [byte] : utf8.encode(char);
            })
            .toList();
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        return joined;
      }
    }
    // For non-ByteLevel BPE (e.g., Metaspace: ▁ → space)
    return joined.replaceAll('\u2581', ' ').trim();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Byte-to-unicode table (GPT-2 style)
  // ────────────────────────────────────────────────────────────────────────────
  static Map<int, String> _buildByteToUnicode() {
    final map = <int, String>{};
    // Printable ASCII + Latin supplement ranges that map directly
    final ranges = [
      [33, 126],   // ! to ~
      [161, 172],  // ¡ to ¬
      [174, 255],  // ® to ÿ
    ];
    int n = 0;
    for (int b = 0; b < 256; b++) {
      bool inRange = false;
      for (final r in ranges) {
        if (b >= r[0] && b <= r[1]) { inRange = true; break; }
      }
      if (inRange) {
        map[b] = String.fromCharCode(b);
      } else {
        map[b] = String.fromCharCode(256 + n);
        n++;
      }
    }
    return map;
  }
}
