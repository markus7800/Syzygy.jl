# Code from Chess.jl which is not yet available through the interface
# other utils


function moveisep(b::Board, m::Move)::Bool
    ptype(pieceon(b, from(m))) == PAWN && to(m) == epsquare(b)
end


function moveiscapture(b::Board, m::Move)::Bool
    pcolor(pieceon(b, to(m))) == -sidetomove(b) || moveisep(b, m)
end


function cancastle(board::Board)
    return cancastlekingside(board, WHITE) || cancastlekingside(board, BLACK) ||
        cancastlequeenside(board, WHITE) || cancastlequeenside(board, BLACK)
end
