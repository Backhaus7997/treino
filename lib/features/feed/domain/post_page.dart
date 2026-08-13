import 'post.dart';

/// One cursor-based page of feed posts.
class PostPage {
  const PostPage({
    required this.posts,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<Post> posts;
  final DateTime? nextCursor;
  final bool hasMore;
}
