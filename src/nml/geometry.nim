import sequtils
import macros, macroutils, math

type NVec*[N: static[int], T] = object
  data*: array[N, T]

proc initNVec*[N: static[int], T](vals: array[N, T]): NVec[N, T] =
  result.data = vals

proc initNVec*[N: static[int], T](val: T): NVec[N, T] =
  for i in 0 ..< N:
    result.data[i] = val

# converter scalarToVec*[N: static[int], T](s: T): NVec[N, T] = initNVec(s)

macro v*(data: varargs[typed]): untyped =
  Call(newTree(nnkBracketExpr, Ident"initNVec", Lit data.len, data[0].gettype),
       data)
  

proc `[]`*[N, T, IT](v: NVec[N, T], index: IT): T = v.data[index]
proc `[]=`*[N, T, IT](v: var NVec[N, T], index: IT, val: T) = v.data[index] = val
  

proc `&`*[N1, N2: static[int],  T1, T2](v1: NVec[N1, T1], v2: NVec[N2, T2]):
    NVec[N1 + N2, T1] =
  for i in 0 ..< N1:
    result[i] = v1[i]
  for i in 0 ..< N2:
    result[i + N1] = v2[i].T1


proc abs*[N: static[int], T](v1: NVec[N, T]): float64 =
  let squares = v1.data.mapIt(it ^ 2)
  squares.foldl(a + b).float64.sqrt()


# this isnt ideal, as the type of intvec/2 should actually be floatvec, but for
# this lib its handy if the first operand determines the result type
template raiseOperator(op: untyped): untyped =
  proc op*[N, T, T2](v: NVec[N, T], val: T2): NVec[N, T] =
    for i, x in v.data:
      result.data[i] = op(x, val).T

  proc op*[N, T, T2](v1: NVec[N, T], v2: NVec[N, T2]): NVec[N, T] =
    for i, (x1, x2) in zip(v1.data, v2.data):
      result.data[i] = op(x1, x2).T

raiseOperator `+`
raiseOperator `-`
raiseOperator `*`
raiseOperator `/`

type
  AbstractRect*[T] = NVec[4, T]
  AbstractPoint*[T] = NVec[2, T]
  AbstractSize*[T] = NVec[2, T]


macro makeProperty(dType: type, name: untyped, index: int): untyped =
  let setIdent = AccQuoted(Ident(name.strval & "="))
  quote do:
    proc `name`*[T](self: `dType`[T]): T = self.data[`index`]
    proc `setIdent`*[T](self: var `dType`[T], val: T) = self.data[`index`] = val

makeProperty AbstractRect, x, 0
makeProperty AbstractRect, y, 1
makeProperty AbstractRect, left, 0
makeProperty AbstractRect, top, 1
makeProperty AbstractRect, w, 2
makeProperty AbstractRect, h, 3

makeProperty AbstractPoint, x, 0
makeProperty AbstractPoint, y, 1

makeProperty AbstractSize, w, 0
makeProperty AbstractSize, h, 1

proc right*[T](r: AbstractRect[T]): T = r.x + r.w
proc bottom*[T](r: AbstractRect[T]): T = r.y + r.h
proc centerX*[T](r: AbstractRect[T]): T = r.x + T(r.w / 2)
proc centerY*[T](r: AbstractRect[T]): T = r.y + T(r.h / 2)
proc center*[T](r: AbstractRect[T]): AbstractPoint[T] = v(r.centerX, r.centerY)
proc pos*[T](r: AbstractRect[T]): AbstractPoint[T] = v(r[0], r[1])
proc size*[T](r: AbstractRect[T]): AbstractSize[T] = v(r[2], r[3])
func contains*[T](r: AbstractRect[T], p: AbstractPoint[T]): bool =
   p.x > r.x and p.x < r.right and p.y > r.y and p.y < r.bottom


proc fitsIn*[T1, T2](a: AbstractSize[T1], b: AbstractSize[T2]): bool =
  a.w <= b.w and a.h <= b.h
