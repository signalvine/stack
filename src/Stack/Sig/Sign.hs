{-# LANGUAGE CPP               #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes        #-}
{-# LANGUAGE TemplateHaskell   #-}

{-|
Module      : Stack.Sig.Sign
Description : Signing Packages
Copyright   : (c) FPComplete.com, 2015
License     : BSD3
Maintainer  : Tim Dysinger <tim@fpcomplete.com>
Stability   : experimental
Portability : POSIX
-}

module Stack.Sig.Sign (sign, signTarBytes) where

#if __GLASGOW_HASKELL__ < 710
import           Control.Applicative ((<$>))
#endif

import           Network.HTTP.Download
import           Control.Monad (when)
import           Control.Monad.Catch
import           Control.Monad.IO.Class
import           Control.Monad.Logger
import           Control.Monad.Trans.Control
import qualified Data.ByteString.Lazy as L
import           Data.Functor (void)
import           Data.List (isSuffixOf)
import           Data.Monoid ((<>))
import qualified Data.Text as T
import           Data.UUID (toString)
import           Data.UUID.V4 (nextRandom)
import           Network.HTTP.Conduit
       (Response(..), RequestBody(..), Request(..), httpLbs, newManager,
        tlsManagerSettings)
import           Network.HTTP.Types (status200, methodPut)
import           Path
import           Path.IO
import           Stack.Package
import qualified Stack.Sig.GPG as GPG
import           Stack.Types
import           System.Directory (getDirectoryContents)
import           System.Process (readProcessWithExitCode)

-- | Sign a haskell package with the given url of the signature
-- service and a path to a tarball.
sign
    :: (MonadCatch m, MonadBaseControl IO m, MonadIO m, MonadMask m, MonadLogger m, MonadThrow m)
    => String -> FilePath -> m ()
sign url filePath = do
    withStackWorkTempDir
        (\tempDir ->
              (do liftIO
                      (void -- TODO extract with haskell-native tar impl (because Windows)
                           (readProcessWithExitCode
                                "tar"
                                [ "xf"
                                , filePath
                                , "-C"
                                , toFilePath tempDir
                                , "--strip"
                                , "1"]
                                []))
                  cabalFiles <-
                      (filter (isSuffixOf ".cabal")) <$>
                      (liftIO
                           (getDirectoryContents
                                (toFilePath tempDir)))
                  when
                      (null cabalFiles)
                      (error ("bogus hackage tarball " <> filePath))
                  cabalFile <-
                      parseRelFile
                          (head cabalFiles)
                  pkg <-
                      cabalFilePackageId
                          (toFilePath
                               (tempDir </> cabalFile))
                  signPackage url pkg filePath))

-- | Sign a haskell package with the given url to the signature
-- service, a package tarball path (package tarball name) and a lazy
-- bytestring of bytes that represent the tarball bytestream.  The
-- function will write the bytes to the path in a temp dir and sign
-- the tarball with GPG.
signTarBytes
    :: (MonadCatch m, MonadBaseControl IO m, MonadIO m, MonadMask m, MonadLogger m, MonadThrow m)
    => String -> FilePath -> L.ByteString -> m ()
signTarBytes url tarFile bs = do
    withStackWorkTempDir
        (\tempDir ->
              (do tarFilePath <- parseRelFile tarFile
                  let tempFilePath = tempDir </> tarFilePath
                      tempFile = toFilePath tempFilePath
                  liftIO (L.writeFile tempFile bs)
                  sign url tempFile))

-- | Sign a haskell package given the url to the signature service, a
-- @PackageIdentifier@ and a file path to the package on disk.
signPackage
    :: (MonadCatch m, MonadBaseControl IO m, MonadIO m, MonadMask m, MonadLogger m, MonadThrow m)
    => String -> PackageIdentifier -> FilePath -> m ()
signPackage url pkg filePath = do
    $logInfo ("GPG signing " <> T.pack filePath)
    sig@(Signature signature) <- GPG.signPackage filePath
    let (PackageIdentifier n v) = pkg
        name = show n
        version = show v
    verify <- GPG.verifyFile sig filePath
    fingerprint <- GPG.fullFingerprint verify
    req <-
        parseUrl
            (url <> "/upload/signature/" <> name <> "/" <> version <> "/" <>
             T.unpack (fingerprintSample fingerprint))
    let put =
            req
            { method = methodPut
            , requestBody = RequestBodyBS signature
            }
    mgr <- liftIO (newManager tlsManagerSettings)
    res <- liftIO (httpLbs put mgr)
    when
        (responseStatus res /= status200)
        (throwM (GPGSignException "unable to sign & upload package"))

withStackWorkTempDir
    :: (MonadCatch m, MonadIO m, MonadMask m, MonadLogger m)
    => (Path Rel Dir -> m ()) -> m ()
withStackWorkTempDir f = do
    uuid <- liftIO nextRandom
    uuidPath <- parseRelDir (toString uuid)
    let tempDir = workDirRel </> $(mkRelDir "tmp") </> uuidPath
    bracket
        (createTree tempDir)
        (const (removeTree tempDir))
        (const (f tempDir))
