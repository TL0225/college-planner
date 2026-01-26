import SwiftUI

struct FlowchartView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Academic Flowchart")
                            .font(DesignSystem.Fonts.main(size: 24, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                        Text("Interactive")
                            .font(DesignSystem.Fonts.main(size: 12))
                            .foregroundColor(DesignSystem.Colors.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.primary.opacity(0.1))
                            .cornerRadius(12)
                    }
                    Text("Visualize prerequisites and graduation pathways.")
                        .font(DesignSystem.Fonts.main(size: 14))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                Spacer()
                
                HStack(spacing: 12) {
                    LegendItem(color: .blue, text: "Core")
                    LegendItem(color: DesignSystem.Colors.info, text: "Finance")
                    LegendItem(color: DesignSystem.Colors.secondary, text: "Marketing")
                }
            }
            .padding()
            .background(DesignSystem.Colors.surface.opacity(0.9))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(hex: "f1f5f9")),
                alignment: .bottom
            )
            
            // Flowchart Canvas
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    // Connections (Simplified with Path)
                    Path { path in
                        // Example paths
                        path.move(to: CGPoint(x: 180, y: 140))
                        path.addCurve(to: CGPoint(x: 320, y: 280), control1: CGPoint(x: 250, y: 140), control2: CGPoint(x: 250, y: 280))
                        
                        path.move(to: CGPoint(x: 180, y: 140))
                        path.addCurve(to: CGPoint(x: 320, y: 420), control1: CGPoint(x: 250, y: 140), control2: CGPoint(x: 250, y: 420))
                        
                        path.move(to: CGPoint(x: 480, y: 280))
                        path.addLine(to: CGPoint(x: 620, y: 280))
                    }
                    .stroke(Color(hex: "cbd5e1"), style: StrokeStyle(lineWidth: 2, dash: [5]))
                    
                    // Nodes
                    HStack(alignment: .top, spacing: 80) {
                        // Year 1 Sem 1
                        VStack(spacing: 40) {
                            Text("Year 1 Sem 1").font(DesignSystem.Fonts.main(size: 14, weight: .bold)).foregroundColor(DesignSystem.Colors.textLight)
                            FlowchartNode(code: "MATH 1110", name: "Calculus I", status: .completed)
                            FlowchartNode(code: "CS 1110", name: "Intro to Computing", status: .completed)
                        }
                        .padding(.top, 80)
                        
                        // Year 1 Sem 2
                        VStack(spacing: 40) {
                            Text("Year 1 Sem 2").font(DesignSystem.Fonts.main(size: 14, weight: .bold)).foregroundColor(DesignSystem.Colors.textLight)
                            FlowchartNode(code: "AEM 2200", name: "Business Mgmt", status: .pending, color: DesignSystem.Colors.info)
                            FlowchartNode(code: "MKT 2000", name: "Prin. Marketing", status: .none, color: DesignSystem.Colors.secondary)
                        }
                        .padding(.top, 120)
                    }
                    .padding(40)
                }
                .frame(width: 1200, height: 800)
            }
        }
    }
}

struct LegendItem: View {
    let color: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(DesignSystem.Fonts.main(size: 12, weight: .semibold)).foregroundColor(DesignSystem.Colors.textLight)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.05), radius: 2)
    }
}

enum NodeStatus {
    case completed, pending, none
}

struct FlowchartNode: View {
    let code: String
    let name: String
    let status: NodeStatus
    var color: Color = DesignSystem.Colors.textLight
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(code)
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.1))
                    .foregroundColor(color)
                    .cornerRadius(4)
                
                Spacer()
                
                if status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.success)
                        .font(.caption)
                } else if status == .pending {
                    Image(systemName: "ellipsis")
                        .foregroundColor(DesignSystem.Colors.primary)
                        .font(.caption)
                }
            }
            
            Text(name)
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(status == .completed ? DesignSystem.Colors.textLight : DesignSystem.Colors.textMain)
                .strikethrough(status == .completed)
        }
        .padding(12)
        .frame(width: 160)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(status == .pending ? DesignSystem.Colors.primary : Color(hex: "e2e8f0"), lineWidth: status == .pending ? 2 : 1)
        )
        .overlay(
            Rectangle()
                .fill(color)
                .frame(width: 4),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
