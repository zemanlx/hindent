{-# LANGUAGE Unsafe #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Main entry point to hindent.
--
-- hindent

module Main where

import           HIndent
import           HIndent.Types
import qualified Data.ByteString as S
import qualified Data.ByteString.Builder as S
import qualified Data.ByteString.Lazy.Char8 as L8
import           Control.Applicative
import           Data.Text (Text)
import qualified Data.Text as T
import           Data.Version (showVersion)
import           Descriptive
import           Descriptive.Options
import           Language.Haskell.Exts hiding (Style,style)
import           Paths_hindent (version)
import           System.Directory
import           System.Environment
import           System.IO
import           Text.Read
import           Control.Exception
import           GHC.IO.Exception
import           Foreign.C.Error

-- | Main entry point.
main :: IO ()
main = do
    args <- getArgs
    case consume options (map T.pack args) of
        Succeeded (style,exts,mfilepath) ->
            case mfilepath of
                Just filepath -> do
                    text <- S.readFile filepath
                    tmpDir <- getTemporaryDirectory
                    (fp,h) <- openTempFile tmpDir "hindent.hs"
                    L8.putStrLn
                                   (either
                                        error
                                        S.toLazyByteString
                                        (reformat style (Just exts) text))
                    hFlush h
                    hClose h
                    let exdev e =
                            if ioe_errno e ==
                               Just
                                   ((\(Errno a) ->
                                          a)
                                        eXDEV)
                                then copyFile fp filepath >> removeFile fp
                                else throw e
                    renameFile fp filepath `catch` exdev
                Nothing ->
                    L8.interact
                           (either error S.toLazyByteString . reformat style (Just exts) . L8.toStrict)
        Failed (Wrap (Stopped Version) _) ->
            putStrLn ("hindent " ++ showVersion version)
        Failed (Wrap (Stopped Help) _) -> putStrLn help
        _ -> error help
  where

help :: [Char]
help =
    "hindent " ++
    T.unpack (textDescription (describe options [])) ++
    "\nVersion " ++ showVersion version ++ "\n" ++
    "The --style option is now ignored, but preserved for backwards-compatibility.\n" ++
    "Johan Tibell is the default and only style."

-- | Options that stop the argument parser.
data Stoppers = Version | Help
  deriving (Show)

-- | Program options.
options :: Monad m
        => Consumer [Text] (Option Stoppers) m (Config,[Extension],Maybe FilePath)
options = ver *> ((,,) <$> style <*> exts <*> file)
  where
    ver =
        stop (flag "version" "Print the version" Version) *>
        stop (flag "help" "Show help" Help)
    style =
        makeStyle <$>
        fmap
            (const defaultConfig)
            (optional
                 (constant "--style" "Style to print with" () *>
                  anyString "STYLE")) <*>
        lineLen
    exts = fmap getExtensions (many (prefix "X" "Language extension"))
    lineLen =
        fmap
            (>>= (readMaybe . T.unpack))
            (optional (arg "line-length" "Desired length of lines"))
    makeStyle s mlen =
        case mlen of
            Nothing -> s
            Just len ->
                s
                { configMaxColumns = len
                }
    file = fmap (fmap T.unpack) (optional (anyString "[<filename>]"))
