-- Copyright (c) 2011 Kevin Cantu <me@kevincantu.org>
--
-- A naive implementation of the Blake cryptographic hash: 
-- use at your own risk.

module Main (main) where

import SHA3.BLAKE
import qualified Data.ByteString.Lazy as BSL
import System
import IO
import Text.Printf
import System.Console.GetOpt
import qualified Data.Text.Lazy as T
import qualified Data.Text.Lazy.Encoding as E
import Data.Word


-- TODO: my function names often suck
-- TODO: may need to add error handling for excessively long inputs per the BLAKE paper)


-- command line options
data Options = Options { help      :: Bool
                       , check_     :: Bool
                       , algorithm :: Integer
                       , salt_      :: [Integer] 
                       }

-- command line defaults
defaultOpts :: Options
defaultOpts = Options { help = False
                      , check_ = False
                      , algorithm = 256
                      , salt_ = [0,0,0,0]
                      }

-- command line description
-- this format is kinda bone headed:
--   [Option short [long] (property setter-function hint) description]
options :: [ OptDescr (Options -> IO Options) ]
options = [ Option "a" ["algorithm"] 
                   (ReqArg
                        (\arg opt -> let alg = read arg :: Integer
                                     in
                                       if elem alg [256,512,224,384]
                                       then return opt { algorithm = alg }
                                       else error "please choose a working algorithm size")
                        "BITS")
                   "256, 512, 224, 384 (default: 256)"

          , Option "c" ["check"] 
                   (NoArg $ \opt -> return opt { check_ = True })
                   "check saved hashes"

          , Option "s" ["salt"] 
                   (ReqArg
                        (\arg opt -> let s = (read ("[" ++ arg ++ "]")) :: [Integer]
                                     in 
                                     if (length $ filter (<0) s) > 0 || length s /= 4
                                     then error "please specify a salt of positive numbers"
                                     else return opt { salt_ = s })
                        "SALT")
                   "positive integer salt, as four words (default: 0,0,0,0)"

          , Option "h" ["help"] 
                   (NoArg  $ \_ -> do
                        prg <- getProgName
                        hPutStrLn stderr $ usageInfo prg options
                        exitWith ExitSuccess)
                   "display this help and exit"

          , Option "v" ["version"] 
                   (NoArg $ \_ -> do
                        me <- getProgName
                        hPutStrLn stderr $ me ++ " version A"
                        exitWith ExitSuccess)
                   "display version and exit"
          ]


-- print a list of numbers as a hex string
hex32 ws = T.pack $ (printf "%08x" ) =<< ws
hex64 ws = T.pack $ (printf "%016x") =<< ws


-- print out the BLAKE hash followed by the file name
printHash getHash salt path message = 
    do
        hash <- return $ getHash (map fromIntegral salt) message
        BSL.putStrLn $ E.encodeUtf8 $ T.concat [hash, T.pack " *", T.pack path]

-- compute a hash in hex
getHashX hex blake salt message = hex $ blake salt $ BSL.unpack message

-- specifically, BLAKE-256
getHash256 :: [Word32] -> BSL.ByteString -> T.Text
getHash256   = getHashX hex32 blake256
printHash256 = printHash getHash256

getHash224 :: [Word32] -> BSL.ByteString -> T.Text
getHash224   = getHashX hex32 blake224
printHash224 = printHash getHash224

-- specifically, BLAKE-512
getHash512   = getHashX hex64 blake512
printHash512 = printHash getHash512

-- specifically, BLAKE-512
getHash384   = getHashX hex64 blake384
printHash384 = printHash getHash384



-- call a function on stdin (as a ByteString)
inF g = BSL.getContents >>= g


-- call a function on a file [or stdin, when "-"] (as a ByteString)
fileF g path =
    if path == "-"
    then inF g
    else BSL.readFile path >>= g


-- apply a function to a list of files and/or stdin
fileMap :: ( BSL.ByteString -> IO () ) -> [FilePath] -> IO ()
fileMap f paths = fileMapWithPath (\_ -> f) paths


-- apply a function (which uses the path) to a list of files and/or stdin
fileMapWithPath :: ( FilePath -> BSL.ByteString -> IO () ) -> [FilePath] -> IO ()
fileMapWithPath f paths = 
    let    
        -- apply f to stdin
        stdinF :: IO ()
        stdinF = BSL.getContents >>= f "-"

        -- apply f to a file (or stdin, when "-")
        fileF :: FilePath -> IO ()
        fileF "-"  = stdinF
        fileF path = BSL.readFile path >>= f path
    in
        case paths of
            [] -> stdinF
            _  -> mapM_ fileF paths


printHashes alg salt paths = let printHash' = case alg of 
                                                256 -> printHash256
                                                224 -> printHash224
                                                512 -> printHash512
                                                384 -> printHash384
                                                _   -> error "unavailable algorithm size"
                            in
                                fileMapWithPath (printHash' salt) paths


checkHashes alg salt paths =
    let
        checkHash' = case alg of
                         256 -> checkHashesInMessage getHash256
                         224 -> checkHashesInMessage getHash224
                         512 -> checkHashesInMessage getHash512
                         384 -> checkHashesInMessage getHash384
                         _   -> error "unavailable algorithm size"
    in
        fileMap ((checkHash' salt) . T.lines . E.decodeUtf8) paths


-- check message (file) of hashes
checkHashesInMessage f salt = mapM_ (checkHash f salt) 



-- check one hash line (i.e., aas98d4a654...5756 *README.txt)
-- generic
checkHash getHash salt line = 
  do
    let [savedHash, path] = T.splitOn (T.pack " *") line

    message <- BSL.readFile (T.unpack path)

    let testedHash = getHash (map fromIntegral salt) $ message

    if testedHash == savedHash
    then BSL.putStrLn $ E.encodeUtf8 $ path `T.append` (T.pack ": OK")
    else BSL.putStrLn $ E.encodeUtf8 $ path `T.append` (T.pack ": FAILED")


main = 
    do 
        args <- getArgs

        -- call getOpt with the option description
        -- returns
        --    actions to do
        --    leftover nonOptions
        --    errors (here, simply _)
        let (actions, nonOptions, _) = getOpt Permute options args

        -- process the defaults with those actions
        -- returns command line properties
        opts <- foldl (>>=) (return defaultOpts) actions
        
        -- assign the results
        -- via destructuring assignment
        let Options { check_     = check
                    , algorithm = algorithmBits
                    , salt_      = salt
                    } = opts

        -- are we in check mode?
        let run = if check 
                  then checkHashes -- ^ verify hashes listed in given files
                  else printHashes -- ^ output hashes of given files

        -- either check or print hashes
        run algorithmBits salt nonOptions


