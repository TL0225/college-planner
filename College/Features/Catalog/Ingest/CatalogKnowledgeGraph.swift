// CatalogKnowledgeGraph.swift
// Feature: Catalog
// Purpose: Academic knowledge graph over requirement AST + prerequisites (P29).

import Foundation

enum CatalogKnowledgeNodeKind: String, Codable, Sendable {
    case program
    case requirement
    case course
    case policy
}

struct CatalogKnowledgeNode: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let kind: CatalogKnowledgeNodeKind
    let label: String
    let confidence: Double?
}

struct CatalogKnowledgeEdge: Codable, Sendable, Hashable {
    let fromID: String
    let toID: String
    let relation: String
    let confidence: Double?
}

struct CatalogKnowledgeGraph: Codable, Sendable, Equatable {
    let nodes: [CatalogKnowledgeNode]
    let edges: [CatalogKnowledgeEdge]
}

enum CatalogKnowledgeGraphBuilder {
    static func build(
        programs: [String],
        requirements: [DegreeRequirement],
        courses: [CatalogCourse]
    ) -> CatalogKnowledgeGraph {
        var nodes: [CatalogKnowledgeNode] = []
        var edges: [CatalogKnowledgeEdge] = []
        var nodeIDs = Set<String>()

        func addNode(_ node: CatalogKnowledgeNode) {
            guard nodeIDs.insert(node.id).inserted else { return }
            nodes.append(node)
        }

        for program in programs {
            let id = "program:\(program.lowercased())"
            addNode(CatalogKnowledgeNode(id: id, kind: .program, label: program, confidence: nil))
        }

        for requirement in requirements {
            let reqID = "req:\(requirement.major.lowercased())||\(requirement.category.lowercased())"
            addNode(CatalogKnowledgeNode(
                id: reqID,
                kind: .requirement,
                label: requirement.category,
                confidence: nil
            ))
            let programID = "program:\(requirement.major.lowercased())"
            edges.append(CatalogKnowledgeEdge(fromID: programID, toID: reqID, relation: "requires", confidence: nil))

            if let predicate = requirement.requirementPredicate {
                appendPredicateEdges(predicate, requirementID: reqID, edges: &edges, addNode: addNode)
            } else if let detailed = requirement.requiredCoursesDetailed {
                for course in detailed {
                    let courseID = "course:\(course.code.lowercased())"
                    addNode(CatalogKnowledgeNode(id: courseID, kind: .course, label: course.code, confidence: nil))
                    edges.append(CatalogKnowledgeEdge(fromID: reqID, toID: courseID, relation: "includes", confidence: nil))
                }
            }
        }

        for course in courses {
            let courseID = "course:\(course.courseCode.lowercased())"
            addNode(CatalogKnowledgeNode(id: courseID, kind: .course, label: course.courseCode, confidence: nil))
            if let prereqText = course.prerequisiteText, !prereqText.isEmpty {
                for token in prereqText.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                    guard !token.isEmpty else { continue }
                    let prereqID = "course:\(token.lowercased())"
                    addNode(CatalogKnowledgeNode(id: prereqID, kind: .course, label: token, confidence: nil))
                    edges.append(CatalogKnowledgeEdge(fromID: courseID, toID: prereqID, relation: "prerequisite", confidence: nil))
                }
            }
        }

        return CatalogKnowledgeGraph(nodes: nodes, edges: edges)
    }

    private static func appendPredicateEdges(
        _ predicate: RequirementPredicate,
        requirementID: String,
        edges: inout [CatalogKnowledgeEdge],
        addNode: (CatalogKnowledgeNode) -> Void
    ) {
        switch predicate.type {
        case .course:
            if let course = predicate.course {
                let courseID = "course:\(course.code.lowercased())"
                addNode(CatalogKnowledgeNode(id: courseID, kind: .course, label: course.code, confidence: nil))
                edges.append(CatalogKnowledgeEdge(fromID: requirementID, toID: courseID, relation: "includes", confidence: nil))
            }
        case .all, .any:
            for child in predicate.children ?? [] {
                appendPredicateEdges(child, requirementID: requirementID, edges: &edges, addNode: addNode)
            }
        }
    }
}
