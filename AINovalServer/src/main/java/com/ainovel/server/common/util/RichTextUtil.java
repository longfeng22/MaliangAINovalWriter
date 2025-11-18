package com.ainovel.server.common.util;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.mantoux.delta.Delta;
import org.mantoux.delta.OpList;
import org.mantoux.delta.Op;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;
import java.util.Map;

public class RichTextUtil {

    private static final Logger log = LoggerFactory.getLogger(RichTextUtil.class);
    private static final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * Extracts plain text from a Quill Delta object.
     *
     * @param delta Quill Delta object
     * @return Plain text string
     */
    public static String deltaToPlainText(Delta delta) {
        if (delta == null) {
            return "";
        }
        // Use the library's provided method to get plain text
        return delta.plainText();
    }

    /**
     * Extracts plain text from a Quill Delta JSON string.
     * Supports both standard Delta object format ("ops": [...]) and direct array format ([...]).
     * Falls back to HTML stripping and then plain text if JSON parsing fails.
     *
     * @param deltaJson Quill Delta JSON string, or HTML, or plain text
     * @return Plain text string
     */
    public static String deltaJsonToPlainText(String deltaJson) {
        if (deltaJson == null || deltaJson.trim().isEmpty()) {
            return "";
        }
        String trimmedJson = deltaJson.trim();

        try {
            // Attempt 1: Parse as standard Delta object {"ops": [...]}
            if (trimmedJson.startsWith("{") && trimmedJson.endsWith("}") && trimmedJson.contains("\"ops\"")) {
                try {
                    Delta delta = objectMapper.readValue(trimmedJson, Delta.class);
                    return deltaToPlainText(delta);
                } catch (JsonProcessingException e) {
                    log.warn("Attempt 1: Failed to parse as standard Delta object ({{\"ops\":...}}). Error: {}. Input snippet: {}", 
                             e.getMessage(), trimmedJson.substring(0, Math.min(trimmedJson.length(), 200)));
                    // Fall through to try other parsing methods
                }
            }
            
            // Attempt 2: Parse as a JSON array of operations [...] using the library's Op and Delta classes
            if (trimmedJson.startsWith("[") && trimmedJson.endsWith("]")) {
                try {
                    List<Op> opJavaList = objectMapper.readValue(trimmedJson, new TypeReference<List<Op>>() {});
                    OpList opList = new OpList(opJavaList); // OpList constructor takes Collection<? extends Op>
                    Delta delta = new Delta(opList);
                    return deltaToPlainText(delta);
                } catch (JsonProcessingException e) {
                    log.warn("Attempt 2: Failed to parse JSON array into List<Op>. Error: {}. Input snippet: {}", 
                             e.getMessage(), trimmedJson.substring(0, Math.min(trimmedJson.length(), 200)));
                    // Fall through to manual map parsing as a robust fallback for arrays
                } catch (Exception e) { // Catch other exceptions like from OpList/Delta constructor or runtime issues
                     log.warn("Attempt 2: Failed to construct OpList/Delta from parsed List<Op>. Error: {}. Input snippet: {}", 
                             e.getMessage(), trimmedJson.substring(0, Math.min(trimmedJson.length(), 200)));
                     // Fall through to manual map parsing
                }

                // Attempt 3 (Fallback for array): Parse as List<Map<String, Object>> and extract inserts manually
                try {
                    List<Map<String, Object>> opsListRaw = objectMapper.readValue(trimmedJson, new TypeReference<List<Map<String, Object>>>() {});
                    StringBuilder sb = new StringBuilder();
                    for (Map<String, Object> opMap : opsListRaw) {
                        if (opMap.containsKey("insert")) {
                            Object insertValue = opMap.get("insert");
                            if (insertValue instanceof String) {
                                sb.append((String) insertValue);
                            } else if (insertValue instanceof Map) {
                                // Delta.plainText() typically adds a newline for embedded objects.
                                sb.append("\n"); 
                            }
                        }
                    }
                    // If opsListRaw was empty (trimmedJson was "[]"), sb will be empty, which is correct.
                    return sb.toString();
                } catch (JsonProcessingException e) {
                    log.warn("Attempt 3 (Fallback): Failed to parse as JSON array of maps. Error: {}. Input snippet: {}", 
                             e.getMessage(), trimmedJson.substring(0, Math.min(trimmedJson.length(), 200)));
                    // Fall through to HTML/plain text check if all Delta JSON parsing fails
                }
            }

            // Final Fallbacks: If not a recognized Delta JSON, try as HTML or plain text
            if (isHtml(trimmedJson)) {
                log.debug("Input not recognized as Delta JSON, attempting to strip HTML. Input snippet: {}", 
                          trimmedJson.substring(0, Math.min(trimmedJson.length(), 200)));
                return stripHtml(trimmedJson);
            }

//            log.debug("Input is not Delta JSON or HTML, returning as is. Input snippet: {}",
//                      trimmedJson.substring(0, Math.min(trimmedJson.length(), 200)));
            return trimmedJson; // Assume plain text or unprocessable format

        } catch (Exception e) { // Catch any other unexpected exceptions during processing
            log.error("Unexpected error in deltaJsonToPlainText. Input snippet: {}. Error: {}. Details: {}", 
                      trimmedJson.substring(0, Math.min(trimmedJson.length(), 200)), e.getMessage(), e.toString());
            // Fallback in case of any other error
            if (isHtml(trimmedJson)) {
                return stripHtml(trimmedJson);
            }
            return trimmedJson; // Final fallback
        }
    }

    /**
     * Basic HTML tag stripping.
     * For complex HTML, consider a dedicated library like JSoup.
     *
     * @param html HTML string
     * @return Text with HTML tags removed
     */
    private static String stripHtml(String html) {
        if (html == null) return "";
        String noHtml = html.replaceAll("<[^>]*>", "");
        // Basic HTML entity decoding
        noHtml = noHtml.replace("&nbsp;", " ")
                       .replace("&lt;", "<")
                       .replace("&gt;", ">")
                       .replace("&amp;", "&")
                       .replace("&quot;", "\"")
                       .replace("&apos;", "'");
        return noHtml;
    }

    /**
     * Basic check to see if a string might be HTML.
     *
     * @param text The string to check
     * @return true if the string heuristically looks like HTML, false otherwise
     */
    private static boolean isHtml(String text) {
        if (text == null) return false;
        String trimmedText = text.trim();
        // Simple heuristic: starts with <, ends with >, and contains at least one tag-like structure.
        return trimmedText.startsWith("<") && trimmedText.endsWith(">") && trimmedText.matches(".*<[^>]+>.*");
    }

    /**
     * 将纯文本转换为Quill Delta JSON格式
     * 
     * @param plainText 纯文本字符串
     * @return Quill Delta JSON格式字符串
     */
    public static String plainTextToDeltaJson(String plainText) {
        if (plainText == null || plainText.isEmpty()) {
            return "[{\"insert\":\"\\n\"}]";
        }
        
        try {
            // 如果文本不以换行符结尾，添加一个（Quill要求）
            String textWithNewline = plainText;
            if (!textWithNewline.endsWith("\n")) {
                textWithNewline += "\n";
            }
            
            // 直接构建Quill Delta格式的Map，然后转换为JSON
            // 这比使用Op类更简单可靠
            Map<String, Object> opMap = new java.util.HashMap<>();
            opMap.put("insert", textWithNewline);
            
            List<Map<String, Object>> ops = new java.util.ArrayList<>();
            ops.add(opMap);
            
            // 转换为JSON字符串（数组格式）
            return objectMapper.writeValueAsString(ops);
        } catch (Exception e) {
            log.error("将纯文本转换为Quill Delta JSON失败: {}", e.getMessage(), e);
            // 发生错误时返回空文档
            return "[{\"insert\":\"\\n\"}]";
        }
    }

    /**
     * 检查字符串是否已经是有效的Quill Delta JSON格式
     * 
     * @param text 待检查的文本
     * @return true如果是有效的Quill Delta JSON，否则返回false
     */
    public static boolean isQuillDeltaJson(String text) {
        if (text == null || text.trim().isEmpty()) {
            return false;
        }
        
        String trimmed = text.trim();
        
        // 检查是否是标准的Quill Delta对象格式 {"ops":[...]}
        if (trimmed.startsWith("{") && trimmed.contains("\"ops\"")) {
            try {
                objectMapper.readValue(trimmed, Delta.class);
                return true;
            } catch (Exception e) {
                return false;
            }
        }
        
        // 检查是否是数组格式 [{"insert":"..."}]
        if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
            try {
                List<Op> ops = objectMapper.readValue(trimmed, new TypeReference<List<Op>>() {});
                return ops != null && !ops.isEmpty();
            } catch (Exception e) {
                return false;
            }
        }
        
        return false;
    }
} 
