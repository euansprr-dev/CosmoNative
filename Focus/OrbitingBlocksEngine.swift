// CosmoOS/Focus/OrbitingBlocksEngine.swift
// Manages related blocks orbiting around a focused document
// Uses semantic search to find related entities

import Foundation
import SwiftUI
import GRDB

@MainActor
class OrbitingBlocksEngine: ObservableObject {
    @Published var blocks: [OrbitingBlock] = []
    @Published var isLoading = false
    
    private let database = CosmoDatabase.shared
    private let semanticSearch = SemanticSearchEngine.shared
    
    // Layout configuration
    private let maxBlocks = 8
    private let leftSideBlocks = 4
    private let rightSideBlocks = 4
    
    // MARK: - Load Related Blocks
    func loadRelatedBlocks(for entity: EntitySelection, count: Int = 6) async {
        isLoading = true
        
        do {
            var relatedBlocks: [OrbitingBlock] = []
            
            // Get the source entity's content for semantic matching
            let sourceContent = await getEntityContent(entity)
            
            // Search for semantically related entities
            // For now, use simple text matching - in production would use vector embeddings
            
            // Get related ideas
            let ideas = try await findRelatedIdeas(to: sourceContent, excluding: entity, limit: 3)
            relatedBlocks.append(contentsOf: ideas)
            
            // Get related content
            let content = try await findRelatedContent(to: sourceContent, excluding: entity, limit: 2)
            relatedBlocks.append(contentsOf: content)
            
            // Get related research
            let research = try await findRelatedResearch(to: sourceContent, excluding: entity, limit: 2)
            relatedBlocks.append(contentsOf: research)
            
            // Get related tasks
            let tasks = try await findRelatedTasks(to: sourceContent, limit: 2)
            relatedBlocks.append(contentsOf: tasks)
            
            // Sort by relevance and limit
            relatedBlocks.sort { $0.relevanceScore > $1.relevanceScore }
            
            // Assign positions (left or right side)
            for (index, _) in relatedBlocks.prefix(maxBlocks).enumerated() {
                relatedBlocks[index].side = index < leftSideBlocks ? .left : .right
                relatedBlocks[index].index = index < leftSideBlocks ? index : index - leftSideBlocks
            }
            
            self.blocks = Array(relatedBlocks.prefix(maxBlocks))
            isLoading = false
            
            print("✅ Loaded \(blocks.count) related blocks for focus mode")
            
        } catch {
            print("❌ Failed to load related blocks: \(error)")
            isLoading = false
        }
    }
    
    // MARK: - Bring More Blocks
    func bringMoreBlocks(count: Int, for entity: EntitySelection) async {
        // Voice command: "Bring 3 more related ideas"
        let sourceContent = await getEntityContent(entity)
        
        do {
            let moreIdeas = try await findRelatedIdeas(
                to: sourceContent,
                excluding: entity,
                limit: count,
                offset: blocks.filter { $0.entityType == .idea }.count
            )
            
            // Add to existing blocks with animation
            for idea in moreIdeas {
                var newBlock = idea
                newBlock.side = blocks.count % 2 == 0 ? .left : .right
                newBlock.index = blocks.filter { $0.side == newBlock.side }.count
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(Double(blocks.count) * 0.1)) {
                    blocks.append(newBlock)
                }
            }
            
            print("✅ Added \(moreIdeas.count) more related blocks")
        } catch {
            print("❌ Failed to bring more blocks: \(error)")
        }
    }
    
    // MARK: - Position Calculation
    func position(for block: OrbitingBlock, in size: CGSize) -> CGPoint {
        let padding: CGFloat = 140
        let verticalSpacing: CGFloat = 120
        let centerY = size.height / 2
        
        // Calculate vertical offset based on index
        let totalOnSide = block.side == .left ? 
            blocks.filter { $0.side == .left }.count : 
            blocks.filter { $0.side == .right }.count
        
        let startY = centerY - CGFloat(totalOnSide - 1) * verticalSpacing / 2
        let y = startY + CGFloat(block.index) * verticalSpacing
        
        // X position based on side
        let x = block.side == .left ? padding : size.width - padding
        
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - Entity Content Retrieval
    private func getEntityContent(_ entity: EntitySelection) async -> String {
        do {
            switch entity.type {
            case .idea:
                if let atom = try await database.asyncRead({ db in
                    try Atom.filter(Column("id") == entity.id)
                        .filter(Column("type") == AtomType.idea.rawValue)
                        .fetchOne(db)
                }) {
                    let idea = IdeaWrapper(atom: atom)
                    return (idea.title ?? "") + " " + idea.content
                }

            case .content:
                if let atom = try await database.asyncRead({ db in
                    try Atom.filter(Column("id") == entity.id)
                        .filter(Column("type") == AtomType.content.rawValue)
                        .fetchOne(db)
                }) {
                    let content = ContentWrapper(atom: atom)
                    return (content.title ?? "") + " " + (content.body ?? "")
                }

            case .research:
                if let atom = try await database.asyncRead({ db in
                    try Atom.filter(Column("id") == entity.id)
                        .filter(Column("type") == AtomType.research.rawValue)
                        .fetchOne(db)
                }) {
                    let research = ResearchWrapper(atom: atom)
                    return (research.title ?? "") + " " + (research.summary ?? "") + " " + research.content
                }

            default:
                break
            }
        } catch {
            print("❌ Failed to get entity content: \(error)")
        }

        return ""
    }
    
    // MARK: - Find Related Entities
    private func findRelatedIdeas(to content: String, excluding: EntitySelection, limit: Int, offset: Int = 0) async throws -> [OrbitingBlock] {
        // Extract key words for matching
        let keywords = extractKeywords(from: content)

        let ideas: [Idea] = try await database.asyncRead { db in
            var query = Atom
                .filter(Column("type") == AtomType.idea.rawValue)
                .filter(Column("is_deleted") == false)
                .order(Column("updated_at").desc)

            // Exclude the current entity if it's an idea
            if excluding.type == .idea {
                query = query.filter(Column("id") != excluding.id)
            }

            return try query.limit(limit, offset: offset).fetchAll(db).map { IdeaWrapper(atom: $0) }
        }

        return ideas.map { idea in
            let relevance = calculateRelevance(content: (idea.title ?? "") + " " + idea.content, keywords: keywords)

            return OrbitingBlock(
                entityType: .idea,
                entityId: idea.id ?? -1,
                title: idea.title ?? "Untitled",
                preview: String(idea.content.prefix(80)),
                relevanceScore: relevance,
                side: .left,
                index: 0
            )
        }
    }
    
    private func findRelatedContent(to content: String, excluding: EntitySelection, limit: Int) async throws -> [OrbitingBlock] {
        let keywords = extractKeywords(from: content)

        let contents: [CosmoContent] = try await database.asyncRead { db in
            var query = Atom
                .filter(Column("type") == AtomType.content.rawValue)
                .filter(Column("is_deleted") == false)
                .order(Column("updated_at").desc)

            if excluding.type == .content {
                query = query.filter(Column("id") != excluding.id)
            }

            return try query.limit(limit).fetchAll(db).map { ContentWrapper(atom: $0) }
        }

        return contents.map { item in
            let relevance = calculateRelevance(content: (item.title ?? "") + " " + (item.body ?? ""), keywords: keywords)

            return OrbitingBlock(
                entityType: .content,
                entityId: item.id ?? -1,
                title: item.title ?? "Untitled",
                preview: item.body?.prefix(80).description,
                relevanceScore: relevance,
                side: .right,
                index: 0
            )
        }
    }
    
    private func findRelatedResearch(to content: String, excluding: EntitySelection, limit: Int) async throws -> [OrbitingBlock] {
        let keywords = extractKeywords(from: content)

        let research: [Research] = try await database.asyncRead { db in
            var query = Atom
                .filter(Column("type") == AtomType.research.rawValue)
                .filter(Column("is_deleted") == false)
                .order(Column("updated_at").desc)

            if excluding.type == .research {
                query = query.filter(Column("id") != excluding.id)
            }

            return try query.limit(limit).fetchAll(db).map { ResearchWrapper(atom: $0) }
        }

        return research.map { item in
            let relevance = calculateRelevance(content: (item.title ?? "") + " " + (item.summary ?? ""), keywords: keywords)

            return OrbitingBlock(
                entityType: .research,
                entityId: item.id ?? -1,
                title: item.title ?? "Untitled",
                preview: item.summary?.prefix(80).description,
                relevanceScore: relevance,
                side: .right,
                index: 0
            )
        }
    }
    
    private func findRelatedTasks(to content: String, limit: Int) async throws -> [OrbitingBlock] {
        let keywords = extractKeywords(from: content)

        let tasks: [CosmoTask] = try await database.asyncRead { db in
            try Atom
                .filter(Column("type") == AtomType.task.rawValue)
                .filter(Column("is_deleted") == false)
                .order(Column("updated_at").desc)
                .limit(limit)
                .fetchAll(db)
                .map { TaskWrapper(atom: $0) }
        }
        
        return tasks.map { task in
            let relevance = calculateRelevance(content: (task.title ?? "") + " " + (task.description ?? ""), keywords: keywords)

            return OrbitingBlock(
                entityType: .task,
                entityId: task.id ?? -1,
                title: task.title ?? "Untitled",
                preview: task.description?.prefix(80).description,
                relevanceScore: relevance,
                side: .left,
                index: 0
            )
        }
    }
    
    // MARK: - Text Analysis
    private func extractKeywords(from text: String) -> [String] {
        // Simple keyword extraction - in production would use NLP
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }
        
        // Remove common stop words
        let stopWords = Set(["the", "and", "for", "that", "this", "with", "are", "was", "were", "been", "have", "has", "had", "does", "did", "will", "would", "could", "should", "from", "your", "their", "what", "when", "where", "which", "who", "whom", "whose", "about"])
        
        return words.filter { !stopWords.contains($0) }
    }
    
    private func calculateRelevance(content: String, keywords: [String]) -> Int {
        let contentLower = content.lowercased()
        var score = 0
        
        for keyword in keywords {
            if contentLower.contains(keyword) {
                score += 1
            }
        }
        
        // Normalize to 1-5 scale
        return min(5, max(1, score / 2 + 1))
    }
}

// MARK: - Orbiting Block Model
struct OrbitingBlock: Identifiable {
    let id = UUID()
    let entityType: EntityType
    let entityId: Int64
    let title: String
    let preview: String?
    var relevanceScore: Int  // 1-5
    var side: OrbitingSide
    var index: Int
}

enum OrbitingSide {
    case left
    case right
}
