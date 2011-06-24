-- Copyright (c) 2011 Kevin Cantu <me@kevincantu.org>
--
-- A naive implementation of the Blake cryptographic hash: 
-- use at your own risk.

module Main (main) where

import SHA3.BLAKE
import Data.Bits
import qualified Data.ByteString.Lazy as BSL
import System
import List
import IO
import Char
import Text.Printf
import Control.Monad
import System.Console.GetOpt
import qualified Data.Text.Lazy as T
import qualified Data.Text.Lazy.IO as TIO
import qualified Data.Text.Lazy.Encoding as E
import qualified Data.ByteString as BS
import Data.Word

data Options = Options { help      :: Bool
                       , check     :: Bool
                       , algorithm :: Integer
                       , salt      :: [Integer] 
                       }

defaultOpts :: Options
defaultOpts = Options { help = False
                      , check = False
                      , algorithm = 256
                      , salt = [0,0,0,0]
                      }

options :: [ OptDescr (Options -> IO Options) ]
options = [ Option "a" ["algorithm"] 
                   (ReqArg
                        (\arg opt -> let alg = read arg :: Integer
                                     in case alg of 
                                            x | x == 256 || x == 512 -> return opt { algorithm = alg }
                                            otherwise -> error "please choose a working algorithm size")
                        "BITS")
                   "256, 512, 224, 384 (default: 256)"

          , Option "c" ["check"] 
                   (NoArg $ \opt -> return opt { check = True })
                   "check saved hashes"

          , Option "s" ["salt"] 
                   (ReqArg
                        (\arg opt -> let s = (read ("[" ++ arg ++ "]")) :: [Integer]
                                     in 
                                     if (length $ filter (<0) s) > 0 || length s /= 4
                                     then error "please specify a salt of positive numbers"
                                     else return opt { salt = s })
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


-- TODO: may need to add error handling 
--       for excessively long inputs per the BLAKE paper)



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

-- specifically, BLAKE-512
getHash512   = getHashX hex64 blake512
printHash512 = printHash getHash512


-- print the hashes of each of a list of files and/or stdin
printHashes 256 salt []    = inF $ printHash256 salt "-"
printHashes 512 salt []    = inF $ printHash512 salt "-"
printHashes 256 salt paths = mapM_ (\path -> (fileF $ printHash256 salt path) path) paths
printHashes 512 salt paths = mapM_ (\path -> (fileF $ printHash512 salt path) path) paths
printHashes _   _    _     = error "unavailable algorithm size"


-- call a function on stdin (as a ByteString)
inF g = BSL.getContents >>= g

-- call a function on a file [or stdin, when "-"] (as a ByteString)
fileF g path =
    if path == "-"
    then inF g
    else BSL.readFile path >>= g


-- check the hashes within each of a list of files and/or stdin
checkHashes 256 salt paths = let 
                               g = (checkHashesInMessage getHash256  64 salt) . T.lines . E.decodeUtf8
                             in 
                               case paths of
                                 []    -> inF g
                                 paths -> mapM_ (fileF g) paths

checkHashes 512 salt paths = let 
                               g = (checkHashesInMessage getHash512 128 salt) . T.lines . E.decodeUtf8
                             in 
                               case paths of
                                 []    -> inF g
                                 paths -> mapM_ (fileF g) paths

checkHashes _   _    _     = error "unavailable algorithm size"


-- check message (file) of hashes
checkHashesInMessage f hsize salt = mapM_ (checkHash f hsize salt) 



-- check one hash line (i.e., aas98d4a654...5756 *README.txt)
-- generic
checkHash getHash hsize salt line = 
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

        -- call getOpt
        let (actions, nonOptions, errors) = getOpt RequireOrder options args

        -- process the defaults with those actions
        opts <- foldl (>>=) (return defaultOpts) actions
        
        -- assign the results
        let Options { check     = check
                    , algorithm = algorithmBits
                    , salt      = salt
                    } = opts

        -- are we in check mode?
        let run = if check 
                  then checkHashes
                  else printHashes

        -- either check or print hashes
        run algorithmBits salt nonOptions


