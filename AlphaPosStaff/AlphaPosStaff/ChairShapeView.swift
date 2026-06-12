import SwiftUI

struct ChairShapeView: View {
    enum Side { case top, bottom, left, right }
    
    let side: Side
    let color: Color
    
    var body: some View {
        Canvas { ctx, size in
            drawChair(ctx: &ctx, size: size)
        }
    }
    
    private func drawChair(ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        
        let backColor  = color.opacity(0.90)
        let seatFill   = color.opacity(0.35)
        let seatStroke = color.opacity(0.80)
        let legColor   = color.opacity(0.65)
        
        switch side {
        case .top:
            let backH = h * 0.28
            let backW = w * 0.50
            let seatH = h * 0.38
            let seatW = w * 0.80
            let legH  = h * 0.26
            let legW  = w * 0.14
            let margin = w * 0.10
            
            let seatY = backH + h * 0.04
            
            var back = Path()
            back.addRoundedRect(in: CGRect(x: (w - backW) / 2, y: 0, width: backW, height: backH), cornerSize: .init(width: 2, height: 2))
            ctx.fill(back, with: .color(backColor))
            
            var seat = Path()
            seat.addRoundedRect(in: CGRect(x: (w - seatW) / 2, y: seatY, width: seatW, height: seatH), cornerSize: .init(width: 2, height: 2))
            ctx.fill(seat, with: .color(seatFill))
            ctx.stroke(seat, with: .color(seatStroke), lineWidth: 1)
            
            let legY = seatY + seatH
            var legL = Path()
            legL.addRoundedRect(in: CGRect(x: margin, y: legY, width: legW, height: legH), cornerSize: .init(width: 1, height: 1))
            ctx.fill(legL, with: .color(legColor))
            var legR = Path()
            legR.addRoundedRect(in: CGRect(x: w - margin - legW, y: legY, width: legW, height: legH), cornerSize: .init(width: 1, height: 1))
            ctx.fill(legR, with: .color(legColor))
            
        case .bottom:
            let backH = h * 0.28
            let backW = w * 0.50
            let seatH = h * 0.38
            let seatW = w * 0.80
            let legH  = h * 0.26
            let legW  = w * 0.14
            let margin = w * 0.10
            
            let seatY = legH + h * 0.04
            
            var legL = Path()
            legL.addRoundedRect(in: CGRect(x: margin, y: 0, width: legW, height: legH), cornerSize: .init(width: 1, height: 1))
            ctx.fill(legL, with: .color(legColor))
            var legR = Path()
            legR.addRoundedRect(in: CGRect(x: w - margin - legW, y: 0, width: legW, height: legH), cornerSize: .init(width: 1, height: 1))
            ctx.fill(legR, with: .color(legColor))
            
            var seat = Path()
            seat.addRoundedRect(in: CGRect(x: (w - seatW) / 2, y: seatY, width: seatW, height: seatH), cornerSize: .init(width: 2, height: 2))
            ctx.fill(seat, with: .color(seatFill))
            ctx.stroke(seat, with: .color(seatStroke), lineWidth: 1)
            
            var back = Path()
            back.addRoundedRect(in: CGRect(x: (w - backW) / 2, y: h - backH, width: backW, height: backH), cornerSize: .init(width: 2, height: 2))
            ctx.fill(back, with: .color(backColor))
            
        case .left:
            let backW2 = w * 0.28
            let backH2 = h * 0.50
            let seatW2 = w * 0.38
            let seatH2 = h * 0.80
            let legW2  = w * 0.26
            let legH2  = h * 0.14
            let margin = h * 0.10
            
            let seatX = backW2 + w * 0.04
            
            var back = Path()
            back.addRoundedRect(in: CGRect(x: 0, y: (h - backH2) / 2, width: backW2, height: backH2), cornerSize: .init(width: 2, height: 2))
            ctx.fill(back, with: .color(backColor))
            
            var seat = Path()
            seat.addRoundedRect(in: CGRect(x: seatX, y: (h - seatH2) / 2, width: seatW2, height: seatH2), cornerSize: .init(width: 2, height: 2))
            ctx.fill(seat, with: .color(seatFill))
            ctx.stroke(seat, with: .color(seatStroke), lineWidth: 1)
            
            let legX = seatX + seatW2
            var legT = Path()
            legT.addRoundedRect(in: CGRect(x: legX, y: margin, width: legW2, height: legH2), cornerSize: .init(width: 1, height: 1))
            ctx.fill(legT, with: .color(legColor))
            var legB = Path()
            legB.addRoundedRect(in: CGRect(x: legX, y: h - margin - legH2, width: legW2, height: legH2), cornerSize: .init(width: 1, height: 1))
            ctx.fill(legB, with: .color(legColor))
            
        case .right:
            let backW2 = w * 0.28
            let backH2 = h * 0.50
            let seatW2 = w * 0.38
            let seatH2 = h * 0.80
            let legW2  = w * 0.26
            let legH2  = h * 0.14
            let margin = h * 0.10
            
            let seatX = legW2 + w * 0.04
            
            var legT = Path()
            legT.addRoundedRect(in: CGRect(x: 0, y: margin, width: legW2, height: legH2), cornerSize: .init(width: 1, height: 1))
            ctx.fill(legT, with: .color(legColor))
            var legB = Path()
            legB.addRoundedRect(in: CGRect(x: 0, y: h - margin - legH2, width: legW2, height: legH2), cornerSize: .init(width: 1, height: 1))
            ctx.fill(legB, with: .color(legColor))
            
            var seat = Path()
            seat.addRoundedRect(in: CGRect(x: seatX, y: (h - seatH2) / 2, width: seatW2, height: seatH2), cornerSize: .init(width: 2, height: 2))
            ctx.fill(seat, with: .color(seatFill))
            ctx.stroke(seat, with: .color(seatStroke), lineWidth: 1)
            
            var back = Path()
            back.addRoundedRect(in: CGRect(x: w - backW2, y: (h - backH2) / 2, width: backW2, height: backH2), cornerSize: .init(width: 2, height: 2))
            ctx.fill(back, with: .color(backColor))
        }
    }
}
