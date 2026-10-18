// text prompts given to the embedding model
// EmbeddingGemma models expect task prefixes for asymmetric retrieval,
// so text queries are prefixed to be compared with image (document) embeddings
// TODO calibrate prompts with EmbeddingGemma 2 model card and on-device tests
class SemanticPrompts {
  static String query(String text) => 'task: search result | query: $text';

  static String label(String label) => query('a photo of $label');
}
