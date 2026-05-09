import Foundation

enum ContextPackAssembler {
    static func assemble(
        request: ContextRetrievalRequest,
        retrievalResults: [ContextRetrievalResult],
        coreMemory: [String],
        workingMemory: [String],
        recallMemory: [String]
    ) -> AgentContextPack {
        let cappedResults = capResults(retrievalResults, tokenBudget: request.tokenBudget)
        var provenance = [
            "Searched \(request.pinnedSourceIDs.count) pinned source(s) for: \(request.query)"
        ]
        provenance.append(contentsOf: cappedResults.map { result in
            let anchor = result.chunk.anchor.map { ":\($0)" } ?? ""
            return "\(result.source.title)\(anchor)"
        })

        let resultTokens = cappedResults.reduce(0) { partial, result in
            partial + result.chunk.tokenCount
        }
        let coreTokens = coreMemory.joined(separator: "\n").count / 4
        let workingTokens = workingMemory.joined(separator: "\n").count / 4
        let recallTokens = recallMemory.joined(separator: "\n").count / 4
        let estimatedTokens = resultTokens + coreTokens + workingTokens + recallTokens

        return AgentContextPack(
            request: request,
            retrievedResults: cappedResults,
            coreMemory: coreMemory,
            workingMemory: workingMemory,
            recallMemory: recallMemory,
            provenanceLines: provenance,
            estimatedTokens: estimatedTokens
        )
    }

    private static func capResults(_ results: [ContextRetrievalResult], tokenBudget: Int) -> [ContextRetrievalResult] {
        var output: [ContextRetrievalResult] = []
        var remaining = max(0, tokenBudget)

        for result in results.sorted(by: { $0.score > $1.score }) {
            guard result.chunk.tokenCount <= remaining || output.isEmpty else { continue }
            output.append(result)
            remaining -= result.chunk.tokenCount
            if remaining <= 0 { break }
        }

        return output
    }
}
