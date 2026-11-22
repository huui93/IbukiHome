import '../../domain/characters/character_card.dart';
import '../../domain/chat/chat_message.dart';
import '../../domain/chat/chat_persona.dart';
import '../../domain/chat/chat_session.dart';
import '../../domain/chat/chat_memory_entry.dart';
import '../../domain/chat/conversation_summary.dart';
import '../../domain/chat/chat_memory_state.dart';
import '../../domain/memory/novel_summary_chunk.dart';
import '../../domain/memory/story_memory_digest.dart';
import '../../domain/outline/outline_node.dart';
import '../../domain/projects/project.dart';
import '../../domain/segments/segment.dart';
import '../../domain/segments/segment_revision.dart';
import '../../domain/world/world_card.dart';
import '../../domain/reader/reader_preferences.dart';

class InMemoryIbukiStore {
  final Map<String, ChatMemoryState> chatMemoryStates = {};
  final Map<String, ChatMemoryUsage> chatMemoryUsage = {};
  final Map<String, Project> _projects = {};
  final Map<String, Segment> _segments = {};
  final Map<String, SegmentRevision> _segmentRevisions = {};
  final Map<String, CharacterCard> _characters = {};
  final Map<String, WorldCard> _worldCards = {};
  final Map<String, ChatSession> _chatSessions = {};
  final Map<String, ChatMessage> _chatMessages = {};
  final Map<String, ChatPersona> _chatPersonas = {};
  final Map<String, OutlineNode> _outlineNodes = {};
  final Map<String, NovelSummaryChunk> _novelSummaryChunks = {};
  final Map<String, StoryMemoryDigest> _storyMemoryDigests = {};
  final Map<String, ReaderPreferences> _readerPreferences = {};
  final Map<String, ReaderProgress> _readerProgress = {};
  final Map<String, ChatMemoryEntry> _chatMemoryEntries = {};
  final Map<String, ConversationSummary> _conversationSummaries = {};

  List<Project> get projects => List.unmodifiable(_projects.values);
  List<Segment> get segments => List.unmodifiable(_segments.values);
  List<SegmentRevision> get segmentRevisions {
    return List.unmodifiable(_segmentRevisions.values);
  }

  List<CharacterCard> get characters => List.unmodifiable(_characters.values);
  List<WorldCard> get worldCards => List.unmodifiable(_worldCards.values);
  List<ChatSession> get chatSessions => List.unmodifiable(_chatSessions.values);
  List<ChatMessage> get chatMessages => List.unmodifiable(_chatMessages.values);
  List<ChatPersona> get chatPersonas => List.unmodifiable(_chatPersonas.values);
  List<OutlineNode> get outlineNodes => List.unmodifiable(_outlineNodes.values);
  List<NovelSummaryChunk> get novelSummaryChunks =>
      List.unmodifiable(_novelSummaryChunks.values);
  List<StoryMemoryDigest> get storyMemoryDigests =>
      List.unmodifiable(_storyMemoryDigests.values);
  List<ChatMemoryEntry> get chatMemoryEntries =>
      List.unmodifiable(_chatMemoryEntries.values);
  List<ConversationSummary> get conversationSummaries =>
      List.unmodifiable(_conversationSummaries.values);

  Project? project(String id) => _projects[id];
  Segment? segment(String id) => _segments[id];
  SegmentRevision? segmentRevision(String id) => _segmentRevisions[id];
  CharacterCard? character(String id) => _characters[id];
  WorldCard? worldCard(String id) => _worldCards[id];
  ChatSession? chatSession(String id) => _chatSessions[id];
  ChatMessage? chatMessage(String id) => _chatMessages[id];
  ChatPersona? chatPersona(String id) => _chatPersonas[id];
  OutlineNode? outlineNode(String id) => _outlineNodes[id];
  NovelSummaryChunk? novelSummaryChunk(String id) => _novelSummaryChunks[id];
  StoryMemoryDigest? storyMemoryDigest(String projectId) =>
      _storyMemoryDigests[projectId];
  ReaderPreferences? readerPreferences(String projectId) =>
      _readerPreferences[projectId];
  ReaderProgress? readerProgress(String projectId) =>
      _readerProgress[projectId];
  ChatMemoryEntry? chatMemoryEntry(String id) => _chatMemoryEntries[id];

  bool hasProject(String id) => _projects.containsKey(id);
  bool hasSegment(String id) => _segments.containsKey(id);
  bool hasSegmentRevision(String id) => _segmentRevisions.containsKey(id);
  bool hasCharacter(String id) => _characters.containsKey(id);
  bool hasWorldCard(String id) => _worldCards.containsKey(id);
  bool hasChatSession(String id) => _chatSessions.containsKey(id);
  bool hasChatMessage(String id) => _chatMessages.containsKey(id);
  bool hasChatPersona(String id) => _chatPersonas.containsKey(id);
  bool hasOutlineNode(String id) => _outlineNodes.containsKey(id);

  void putProject(Project project) {
    _projects[project.id] = project;
  }

  void removeProject(String id) {
    _projects.remove(id);
  }

  void putSegment(Segment segment) {
    _segments[segment.id] = segment;
  }

  void putSegmentRevision(SegmentRevision revision) {
    _segmentRevisions[revision.id] = revision;
  }

  void putCharacter(CharacterCard character) {
    _characters[character.id] = character;
  }

  void removeCharacter(String id) {
    _characters.remove(id);
  }

  void putWorldCard(WorldCard card) {
    _worldCards[card.id] = card;
  }

  void putChatSession(ChatSession session) {
    _chatSessions[session.id] = session;
  }

  void putChatMessage(ChatMessage message) {
    _chatMessages[message.id] = message;
  }

  void putChatPersona(ChatPersona persona) {
    _chatPersonas[persona.id] = persona;
  }

  void putOutlineNode(OutlineNode node) {
    _outlineNodes[node.id] = node;
  }

  void putNovelSummaryChunk(NovelSummaryChunk chunk) {
    _novelSummaryChunks[chunk.id] = chunk;
  }

  void removeNovelSummaryChunk(String id) => _novelSummaryChunks.remove(id);

  void putStoryMemoryDigest(StoryMemoryDigest digest) {
    _storyMemoryDigests[digest.projectId] = digest;
  }

  void putReaderPreferences(ReaderPreferences preferences) {
    _readerPreferences[preferences.projectId] = preferences;
  }

  void putReaderProgress(ReaderProgress progress) {
    _readerProgress[progress.projectId] = progress;
  }

  void putChatMemoryEntry(ChatMemoryEntry entry) {
    _chatMemoryEntries[entry.id] = entry;
  }

  void putConversationSummary(ConversationSummary summary) {
    _conversationSummaries[summary.id] = summary;
  }

  void clear() {
    chatMemoryStates.clear();
    chatMemoryUsage.clear();
    _projects.clear();
    _segments.clear();
    _segmentRevisions.clear();
    _characters.clear();
    _worldCards.clear();
    _chatSessions.clear();
    _chatMessages.clear();
    _chatPersonas.clear();
    _outlineNodes.clear();
    _novelSummaryChunks.clear();
    _storyMemoryDigests.clear();
    _readerPreferences.clear();
    _readerProgress.clear();
    _chatMemoryEntries.clear();
    _conversationSummaries.clear();
  }
}
