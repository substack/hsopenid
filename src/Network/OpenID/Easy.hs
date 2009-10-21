
--------------------------------------------------------------------------------
-- |
-- Module      : Network.OpenID.Easy
-- Copyright   : (c) James Halliday, 2009
-- License     : BSD3
--
-- Maintainer  : James Halliday <substack@gmail.com>
-- Stability   : 
-- Portability : 
--

module Network.OpenID.Easy (
    Config(..),
    Session(..),
    auth, verify, config
) where

import Network.OpenID
import Network.Socket (withSocketsDo)
 
-- | Provides configuration settings for verify and auth. For now, this is just
--   the errors which may be thrown by either.
data Config = Config {
    verifyError :: String -> IO (),
    normalizeError :: IO Session,
    discoverError, associateError :: String -> IO Session
}

-- | Provide default configuration with error handlers that just fail with a
--   useful message when errors happen. This behavior is what most people would
--   probably end up writing themselves anyways.
config :: Config
config = Config {
    normalizeError = fail "Unable to normalize identifier",
    discoverError = fail . ("Discovery Error: " ++),
    associateError = fail . ("Associate Error: " ++),
    verifyError = fail . ("Verify Error: " ++)
}

-- | Wrap up all the data necessary to do a verify into one place, plus some
--   extra useful stuff.
data Session = Session {
    -- | the authentication uri to send the client off to
    sAuthURI :: String,
    -- | the OpenID provider as a string
    sProvider :: String,
    -- | the normalized OpenID identity as a string
    sIdentity :: String,
    -- | the uri the client will come back to after authenticating
    sReturnTo :: String,
    -- | the association map manager thing used internally
    sAssocMap :: AssociationMap
} deriving (Read,Show)

-- | Given a configuration, identity, and return uri,
--   contact the remote provider to create a Session object encapsulating the
--   useful bits of data to pass along to verify and also to pick out the
--   normalized identity from.
auth :: Config -> String -> String -> IO Session
auth config ident returnTo = withSocketsDo $ do
    -- this bit is heavily based on the old examples/test.hs
    case normalizeIdentifier (Identifier ident) of
        Nothing -> normalizeError config
        Just normalizedIdent -> do
            let resolve = makeRequest True
            rpi <- discover resolve normalizedIdent
            case rpi of
                Left err -> discoverError config $ show err
                Right (provider,identifier) -> do
                    -- either an error or an association manager
                    eam <- associate emptyAssociationMap True resolve provider
                    case eam of
                        Left err -> associateError config $ show err
                        Right am ->
                            return $ Session {
                                sAuthURI = show $ authenticationURI
                                    am Setup provider identifier returnTo Nothing,
                                sProvider = show $ providerURI provider,
                                sIdentity = getIdentifier identifier,
                                sReturnTo = returnTo,
                                sAssocMap = am
                            }

-- use this to resolve stuff in auth and verify
resolver :: Resolver IO
resolver = makeRequest True

-- | Given a configuration, a Session generated by auth, and the uri that the
--   client came back on from the provider, make sure the client properly
--   authenticated by running verifyError on failure to verify the credentials.
verify :: Config -> Session -> String -> IO ()
verify config session uri = do
    let
        params = parseParams uri
    verified <- verifyAuthentication
        (sAssocMap session)
        params
        (sReturnTo session)
        resolver
    case verified of
        Left err -> verifyError config $ show err
        Right _ -> return ()