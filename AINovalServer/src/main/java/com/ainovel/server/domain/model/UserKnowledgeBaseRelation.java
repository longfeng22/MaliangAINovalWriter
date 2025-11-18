package com.ainovel.server.domain.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.LocalDateTime;

/**
 * 用户知识库关系
 * 用于维护用户与知识库的多对多关系
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "user_knowledge_base_relations")
@CompoundIndex(name = "user_kb_idx", def = "{'userId': 1, 'knowledgeBaseId': 1}", unique = true)
public class UserKnowledgeBaseRelation {
    
    @Id
    private String id;
    
    /**
     * 用户ID
     */
    @Indexed
    private String userId;
    
    /**
     * 知识库ID
     */
    @Indexed
    private String knowledgeBaseId;
    
    /**
     * 添加方式
     * AUTO_EXTRACT - 自动拆书添加
     * MANUAL_ADD - 手动添加
     */
    private AddType addType;
    
    /**
     * 添加时间
     */
    @CreatedDate
    private LocalDateTime addedAt;
    
    /**
     * 最后使用时间（用于排序）
     */
    private LocalDateTime lastUsedAt;
    
    /**
     * 备注
     */
    private String notes;
    
    /**
     * 添加方式枚举
     */
    public enum AddType {
        AUTO_EXTRACT("自动拆书添加"),
        MANUAL_ADD("手动添加");
        
        private final String description;
        
        AddType(String description) {
            this.description = description;
        }
        
        public String getDescription() {
            return description;
        }
    }
}


