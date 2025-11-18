package com.ainovel.server.service.impl;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.mongodb.core.ReactiveMongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.stereotype.Service;

import com.ainovel.server.domain.model.KnowledgeChunk;
import com.ainovel.server.repository.KnowledgeChunkRepository;
import com.ainovel.server.service.EmbeddingService;
import com.ainovel.server.service.KnowledgeService;
import com.ainovel.server.service.NovelService;
import com.ainovel.server.service.vectorstore.SearchResult;
import com.ainovel.server.service.vectorstore.VectorStore;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * 知识库服务实现类
 * 负责管理小说内容的向量化存储和检索
 */
@Slf4j
@Service
public class KnowledgeServiceImpl implements KnowledgeService {

    private final ReactiveMongoTemplate mongoTemplate;
    private final KnowledgeChunkRepository knowledgeChunkRepository;
    private final EmbeddingService embeddingService;
    private final NovelService novelService;
    private final VectorStore vectorStore;
    
    // 文本分块大小（字符数）
    private static final int CHUNK_SIZE = 1000;
    // 分块重叠大小（字符数）
    private static final int CHUNK_OVERLAP = 200;
    // 默认检索限制数量
    private static final int DEFAULT_SEARCH_LIMIT = 5;
    
    @Autowired
    public KnowledgeServiceImpl(
            ReactiveMongoTemplate mongoTemplate,
            KnowledgeChunkRepository knowledgeChunkRepository,
            EmbeddingService embeddingService,
            NovelService novelService,
            VectorStore vectorStore) {
        this.mongoTemplate = mongoTemplate;
        this.knowledgeChunkRepository = knowledgeChunkRepository;
        this.embeddingService = embeddingService;
        this.novelService = novelService;
        this.vectorStore = vectorStore;
    }
    
    @Override
    public Mono<KnowledgeChunk> indexContent(String novelId, String sourceType, String sourceId, String content) {
        log.info("为小说 {} 索引内容，源类型: {}, 源ID: {}", novelId, sourceType, sourceId);
        
        // 首先删除该源的现有知识块
        return deleteKnowledgeChunks(novelId, sourceType, sourceId)
                .then(Mono.defer(() -> {
                    // 分块处理内容
                    List<String> chunks = splitTextIntoChunks(content, CHUNK_SIZE, CHUNK_OVERLAP);
                    
                    // 创建知识块并存储
                    return Flux.fromIterable(chunks)
                            .flatMap(chunk -> {
                                // 创建知识块
                                KnowledgeChunk knowledgeChunk = new KnowledgeChunk();
                                knowledgeChunk.setId(UUID.randomUUID().toString());
                                knowledgeChunk.setNovelId(novelId);
                                knowledgeChunk.setSourceType(sourceType);
                                knowledgeChunk.setSourceId(sourceId);
                                knowledgeChunk.setContent(chunk);
                                
                                // 生成向量嵌入
                                return generateEmbedding(chunk)
                                        .map(embedding -> {
                                            knowledgeChunk.setVectorEmbedding(embedding);
                                            return knowledgeChunk;
                                        })
                                        .flatMap(knowledgeChunkRepository::save)
                                        .flatMap(savedChunk -> {
                                            // 同时存储到向量存储
                                            return vectorStore.storeKnowledgeChunk(savedChunk)
                                                    .thenReturn(savedChunk);
                                        });
                            })
                            .collectList()
                            .map(savedChunks -> {
                                log.info("为小说 {} 索引了 {} 个知识块", novelId, savedChunks.size());
                                return savedChunks.isEmpty() ? null : savedChunks.get(0);
                            });
                }));
    }
    
    @Override
    public Mono<String> retrieveRelevantContext(String query, String novelId) {
        return retrieveRelevantContext(query, novelId, DEFAULT_SEARCH_LIMIT);
    }
    
    @Override
    public Mono<String> retrieveRelevantContext(String query, String novelId, int limit) {
        log.info("为小说 {} 检索相关上下文，查询: {}, 限制: {}", novelId, query, limit);
        
        return semanticSearch(query, novelId, limit)
                .map(KnowledgeChunk::getContent)
                .collectList()
                .map(contents -> {
                    if (contents.isEmpty()) {
                        return "没有找到相关上下文。";
                    }
                    
                    // 组装上下文
                    StringBuilder contextBuilder = new StringBuilder();
                    for (int i = 0; i < contents.size(); i++) {
                        contextBuilder.append("片段 ").append(i + 1).append(":\n");
                        contextBuilder.append(contents.get(i)).append("\n\n");
                    }
                    
                    return contextBuilder.toString().trim();
                });
    }
    
    @Override
    public Flux<KnowledgeChunk> semanticSearch(String query, String novelId, int limit) {
        log.info("为小说 {} 进行语义搜索，查询: {}, 限制: {}", novelId, query, limit);
        
        // 生成查询向量
        return embeddingService.generateEmbedding(query)
                .flatMapMany(queryVector -> {
                    // 使用向量存储进行搜索
                    return vectorStore.searchByNovelId(queryVector, novelId, limit)
                            .flatMap(result -> {
                                // 根据ID获取完整的知识块
                                String chunkId = (String) result.getMetadata().get("id");
                                if (chunkId != null) {
                                    return knowledgeChunkRepository.findById(chunkId);
                                } else {
                                    // 如果没有ID，创建一个临时知识块
                                    KnowledgeChunk chunk = new KnowledgeChunk();
                                    chunk.setContent(result.getContent());
                                    chunk.setNovelId(novelId);
                                    
                                    // 尝试从元数据中获取其他信息
                                    if (result.getMetadata().containsKey("sourceType")) {
                                        chunk.setSourceType((String) result.getMetadata().get("sourceType"));
                                    }
                                    if (result.getMetadata().containsKey("sourceId")) {
                                        chunk.setSourceId((String) result.getMetadata().get("sourceId"));
                                    }
                                    
                                    return Mono.just(chunk);
                                }
                            });
                });
    }
    
    @Override
    public Mono<Void> deleteKnowledgeChunks(String novelId, String sourceType, String sourceId) {
        log.info("删除小说 {} 的知识块，源类型: {}, 源ID: {}", novelId, sourceType, sourceId);
        
        // 从MongoDB删除
        Query query = new Query();
        query.addCriteria(Criteria.where("novelId").is(novelId));
        
        if (sourceType != null && !sourceType.isEmpty()) {
            query.addCriteria(Criteria.where("sourceType").is(sourceType));
            
            if (sourceId != null && !sourceId.isEmpty()) {
                query.addCriteria(Criteria.where("sourceId").is(sourceId));
                
                // 从向量存储删除
                return mongoTemplate.remove(query, KnowledgeChunk.class)
                        .then(vectorStore.deleteBySourceId(novelId, sourceType, sourceId));
            }
            
            // 从向量存储删除（按源类型）
            return mongoTemplate.remove(query, KnowledgeChunk.class)
                    .then(Mono.empty()); // 向量存储目前不支持按源类型删除
        }
        
        // 从向量存储删除（按小说ID）
        return mongoTemplate.remove(query, KnowledgeChunk.class)
                .then(vectorStore.deleteByNovelId(novelId));
    }
    
    @Override
    public Mono<Void> reindexNovel(String novelId) {
        log.info("重新索引小说 {}", novelId);
        
        // 首先删除该小说的所有知识块
        return deleteKnowledgeChunks(novelId, null, null)
                .then(Mono.defer(() -> {
                    // 获取小说的所有场景内容
                    return novelService.getNovelScenes(novelId)
                            .flatMap(scene -> indexContent(novelId, "scene", scene.getId(), scene.getContent()))
                            .then();
                }))
                .then(Mono.defer(() -> {
                    // 获取小说的所有角色信息
                    return novelService.getNovelCharacters(novelId)
                            .flatMap(character -> {
                                String content = character.getName() + "\n" + character.getDescription();
                                return indexContent(novelId, "character", character.getId(), content);
                            })
                            .then();
                }));
    }
    
    /**
     * 生成文本的向量嵌入
     * @param text 文本内容
     * @return 向量嵌入
     */
    private Mono<KnowledgeChunk.VectorEmbedding> generateEmbedding(String text) {
        // 使用嵌入服务生成向量嵌入
        return embeddingService.generateEmbedding(text)
                .map(vector -> {
                    KnowledgeChunk.VectorEmbedding embedding = new KnowledgeChunk.VectorEmbedding();
                    embedding.setVector(vector);
                    embedding.setDimension(vector.length);
                    embedding.setModel("text-embedding-3-small"); // 默认使用OpenAI的嵌入模型
                    return embedding;
                });
    }
    
    /**
     * 将文本分割成重叠的块
     * @param text 原始文本
     * @param chunkSize 块大小
     * @param overlap 重叠大小
     * @return 文本块列表
     */
    private List<String> splitTextIntoChunks(String text, int chunkSize, int overlap) {
        if (text == null || text.isEmpty()) {
            return List.of();
        }
        
        java.util.List<String> chunks = new java.util.ArrayList<>();
        int textLength = text.length();
        
        // 如果文本长度小于块大小，直接返回整个文本
        if (textLength <= chunkSize) {
            chunks.add(text);
            return chunks;
        }
        
        // 分块处理
        int startIndex = 0;
        while (startIndex < textLength) {
            int endIndex = Math.min(startIndex + chunkSize, textLength);
            
            // 尝试在句子或段落边界处分割
            if (endIndex < textLength) {
                // 寻找最近的句子结束符
                int sentenceEnd = findSentenceEnd(text, endIndex);
                if (sentenceEnd > 0) {
                    endIndex = sentenceEnd;
                }
            }
            
            chunks.add(text.substring(startIndex, endIndex));
            
            // 计算下一个块的起始位置，考虑重叠
            startIndex = endIndex - overlap;
            if (startIndex < 0) startIndex = 0;
            
            // 如果剩余文本长度小于重叠大小，直接结束
            if (textLength - startIndex <= overlap) {
                break;
            }
        }
        
        return chunks;
    }
    
    /**
     * 在文本中寻找最近的句子结束符
     * @param text 文本
     * @param position 起始位置
     * @return 句子结束位置，如果没有找到则返回-1
     */
    private int findSentenceEnd(String text, int position) {
        // 向前搜索100个字符范围内的句子结束符
        int searchLimit = Math.max(0, position - 100);
        for (int i = position; i >= searchLimit; i--) {
            if (i < text.length() && (text.charAt(i) == '。' || text.charAt(i) == '.' || 
                text.charAt(i) == '!' || text.charAt(i) == '?' || 
                text.charAt(i) == '！' || text.charAt(i) == '？' || 
                text.charAt(i) == '\n')) {
                return i + 1;
            }
        }
        return -1;
    }
} 