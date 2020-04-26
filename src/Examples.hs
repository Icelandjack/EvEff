{-# LANGUAGE  TypeOperators, FlexibleContexts, Rank2Types  #-}
-- Nice Examples for the paper
import EffEvScopedOP

operation op = opNormal op
function f   = opTail f
value x      = function (\() -> return x)

-- BEGIN:reader
data Reader a e ans = Reader { ask :: Op () a e ans }
-- END:reader

-- BEGIN:readerhr
hr :: a -> Reader a e ans 
hr x = Reader{ ask = operation (\ () resume -> resume x) }
-- END:readerhr

-- BEGIN:readerh
reader :: a -> Eff (Reader a :* e) ans -> Eff e ans
reader x action 
  = handler (hr x) action
-- END:readerh

-- when to introduce function
-- show type of: handler :: h e ans -> Eff (h :* e) -> Eff e

-- BEGIN:readerex1
sample1 = reader "world" $
          do s <- perform ask ()
             return ("hello " ++ s)
-- END:readerex1

-- BEGIN:readergreet
greet :: (Reader String :? e) => Eff e String
greet = do s <- perform ask ()
           return ("hello " ++ s)
-- END:readergreet

-- BEGIN:readerex
helloWorld :: Eff e String
helloWorld = reader "world" $
             do greet
-- END:readerex

-- BEGIN:exn
data Exn e ans = Exn { failure :: forall a. Op () a e ans }

except :: Eff (Exn :* e) (Maybe ans) -> Eff e (Maybe ans)
except = handler $ Exn{ failure = operation (\ () resume -> return Nothing) }
-- END:exn

-- BEGIN:exnex
safeDiv :: (Exn :? e) => Int -> Int -> Eff e Int
safeDiv x 0 = perform failure ()
safeDiv x y = return (x `div` y)

safeHead :: (Exn :? e) => String -> Eff e Char
safeHead []    = perform failure ()
safeHead (x:_) = return x

sample3 = reader "" $
          except $
          do s <- perform ask ()
             c <- safeHead s
             return (Just c)
-- END:exnex

-- introduce handlerRet

-- BEGIN:state
data State a e ans = State { get :: Op () a e ans, put :: Op a () e ans }

state :: a -> Eff (State a :* e) ans -> Eff e ans
state init
  = handleLocal init $ \loc ->
    State{ get = function (\() -> localGet loc init),
           put = function (\x -> localSet loc x)   }
-- END:state

-- BEGIN:stateex
add :: (State Int :? e) => Int -> Eff e Int
add i = do j <- perform get ()
           perform put (i + j)
           return j

adder = state (1::Int) $
        do add 41
           i <- perform get ()
           return ("the final state is: " ++ show (i::Int))
-- END:stateex


-- BEGIN:pstate
pstate :: a -> Eff (State a :* e) ans -> Eff e ans
pstate init
  = handleParam init $ \function operation ->
    State{ get = function (\() p -> return (p,p)),
           put = function (\x p  -> return ((),x))  }

padder = pstate (1::Int) $
         do add 41
            i <- perform get ()
            return ("the final state is: " ++ show (i::Int))
-- END:pstate

-- BEGIN:output
data Output e ans = Output { out :: Op String () e ans }

output :: Eff (Output :* e) ans -> Eff e (ans,String)
output
  = handleLocalRet [] (\x ss -> (x,concat ss)) $ \loc ->
    Output { out = opTail (\x -> localUpdate loc (x:)) }

collect = output $
          do perform out "hi"
             perform out "there"
-- END:output




-- BEGIN:util
handler h action
  = handle h action

handlerRet f h action
  = handler h (do x <- action; return (f x))

localUpdate :: Local a -> (a -> a) -> Eff e ()
localUpdate loc f
  = do x <- localGet loc ()
       localSet loc (f x)

handleLocal :: a -> (Local a -> h e ans) -> Eff (h :* e) ans -> Eff e ans
handleLocal init hcreate action
    = local init (\loc -> handle (hcreate loc) action)

handleLocalRet :: a -> (b -> a -> ans) -> (Local a -> h e ans) -> Eff (h :* e) b -> Eff e ans
handleLocalRet init ret hcreate action
    = local init (\loc -> handle (hcreate loc) (do x <- action; l <- localGet loc init; return (ret x l)))
-- END:util

-- BEGIN:handleParam
newtype Parameter s a = Parameter (Local a)

pNormal :: Parameter s p -> (a -> p -> ((b,p) -> Eff e ans) -> Eff e ans) -> Op a b e ans
pNormal (Parameter p) op
  = opNormal (\x k -> do vx <- localGet p x
                         let kp (y,vy) = do{ localSet p vy; k y }
                         op x vx kp)

pTail :: Parameter s p -> (a -> p -> Eff e (b,p)) -> Op a b e ans
pTail (Parameter p) op
 = opTail (\x -> do vx <- localGet p x
                    (y,vy) <- op x vx
                    localSet p vy
                    return y)

handleParam :: p -> ((forall a b. ((a -> p -> Eff e (b,p)) -> Op a b e ans)) ->
                     (forall a b. ((a -> p -> ((b,p) -> Eff e ans) -> Eff e ans) -> Op a b e ans)) -> h e ans)
                 -> Eff (h :* e) ans -> Eff e ans
handleParam init hcreate action
  = local init $ \local ->
    let p = Parameter local
    in handle (hcreate (pTail p) (pNormal p)) action

-- END:handleParam