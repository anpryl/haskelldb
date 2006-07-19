-----------------------------------------------------------
-- |
-- Module      :  Database.HaskellDB.HDBC
-- Copyright   :  HWT Group 2003, 
--                Bjorn Bringert 2005-2006
-- License     :  BSD-style
-- 
-- Maintainer  :  haskelldb-users@lists.sourceforge.net
-- Stability   :  experimental
-- Portability :  portable
--
-- HDBC interface for HaskellDB
--
-----------------------------------------------------------

module Database.HaskellDB.HDBC (hdbcConnect) where

import Database.HaskellDB
import Database.HaskellDB.Database
import Database.HaskellDB.Sql
import Database.HaskellDB.Sql.Print
import Database.HaskellDB.PrimQuery
import Database.HaskellDB.Query
import Database.HaskellDB.FieldType

import Database.HDBC as HDBC hiding (toSql)

import Control.Monad.Trans (MonadIO, liftIO)
import Data.Char (toLower)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Maybe (fromMaybe)

-- | Run an action on a HDBC Connection and close the connection.
hdbcConnect :: MonadIO m => IO Connection -- ^ connection function
	    -> (Database -> m a) -> m a
hdbcConnect connect action = 
    do
    conn <- liftIO $ handleSqlError connect
    x <- action (mkDatabase conn)
    -- FIXME: should we really commit here?
    liftIO $ HDBC.commit conn
    liftIO $ handleSqlError (HDBC.disconnect conn)
    return x

mkDatabase :: Connection -> Database
mkDatabase connection
    = Database { dbQuery	= hdbcQuery connection,
    		 dbInsert	= hdbcInsert connection,
		 dbInsertQuery 	= hdbcInsertQuery connection,
		 dbDelete	= hdbcDelete connection,
		 dbUpdate	= hdbcUpdate connection,
		 dbTables       = hdbcTables connection,
		 dbDescribe     = hdbcDescribe connection,
		 dbTransaction  = hdbcTransaction connection,
		 dbCreateDB     = hdbcCreateDB connection,
		 dbCreateTable  = hdbcCreateTable connection,
		 dbDropDB       = hdbcDropDB connection,
		 dbDropTable    = hdbcDropTable connection
	       }

hdbcQuery :: GetRec er vr => 
	     Connection 
	  -> PrimQuery 
	  -> Rel er 
	  -> IO [Record vr]
hdbcQuery connection qtree rel = hdbcPrimQuery connection sql scheme rel
    where
      sql = show (ppSql (toSql qtree))  
      scheme = attributes qtree

hdbcInsert :: Connection -> TableName -> Assoc -> IO ()
hdbcInsert conn table assoc = 
    hdbcPrimExecute conn $ show $ ppInsert $ toInsert table assoc

hdbcInsertQuery :: Connection -> TableName -> PrimQuery -> IO ()
hdbcInsertQuery conn table assoc = 
    hdbcPrimExecute conn $ show $ ppInsert $ toInsertQuery table assoc

hdbcDelete :: Connection -> TableName -> [PrimExpr] -> IO ()
hdbcDelete conn table exprs = 
    hdbcPrimExecute conn $ show $ ppDelete $ toDelete table exprs

hdbcUpdate :: Connection -> TableName -> [PrimExpr] -> Assoc -> IO ()
hdbcUpdate conn table criteria assigns = 
    hdbcPrimExecute conn $ show $ ppUpdate $ toUpdate table criteria assigns

hdbcTables :: Connection -> IO [TableName]
hdbcTables conn = handleSqlError $ HDBC.getTables conn

hdbcDescribe :: Connection -> TableName -> IO [(Attribute,FieldDesc)]
hdbcDescribe conn table = 
    handleSqlError $ do
                     cs <- HDBC.describeTable conn table
                     return [(n,colDescToFieldDesc c) | (n,c) <- cs]

colDescToFieldDesc :: SqlColDesc -> FieldDesc
colDescToFieldDesc c = (t, nullable)
    where 
    nullable = fromMaybe True (colNullable c)
    string = maybe StringT BStrT (colSize c)
    t = case colType c of
            SqlCharT          -> string
            SqlVarCharT       -> string
            SqlLongVarCharT   -> string
            SqlWCharT	      -> string
            SqlWVarCharT      -> string
            SqlWLongVarCharT  -> string
            SqlDecimalT       -> IntegerT
            SqlNumericT       -> IntegerT
            SqlSmallIntT      -> IntT
            SqlIntegerT	      -> IntT
            SqlRealT	      -> DoubleT
            SqlFloatT	      -> DoubleT
            SqlDoubleT	      -> DoubleT
            SqlBitT	      -> BoolT
            SqlTinyIntT	      -> IntT
            SqlBigIntT	      -> IntT
            SqlBinaryT	      -> string
            SqlVarBinaryT     -> string
            SqlLongVarBinaryT -> string
            SqlDateT          -> CalendarTimeT
            SqlTimeT          -> CalendarTimeT
            SqlTimestampT     -> CalendarTimeT
            SqlUTCDateTimeT   -> CalendarTimeT
            SqlUTCTimeT       -> CalendarTimeT
            SqlIntervalT _    -> string
            SqlGUIDT          -> string
            SqlUnknownT _     -> string

hdbcCreateDB :: Connection -> String -> IO ()
hdbcCreateDB conn name 
    = hdbcPrimExecute conn $ show $ ppCreate $ toCreateDB name

hdbcCreateTable :: Connection -> TableName -> [(Attribute,FieldDesc)] -> IO ()
hdbcCreateTable conn name attrs
    = hdbcPrimExecute conn $ show $ ppCreate $ toCreateTable name attrs

hdbcDropDB :: Connection -> String -> IO ()
hdbcDropDB conn name 
    = hdbcPrimExecute conn $ show $ ppDrop $ toDropDB name

hdbcDropTable :: Connection -> TableName -> IO ()
hdbcDropTable conn name
    = hdbcPrimExecute conn $ show $ ppDrop $ toDropTable name

-- | HDBC implementation of 'Database.dbTransaction'.
hdbcTransaction :: Connection -> IO a -> IO a
hdbcTransaction conn action = 
    handleSqlError $ HDBC.withTransaction conn (\_ -> action)


-----------------------------------------------------------
-- Primitive operations
-----------------------------------------------------------

type HDBCRow = Map String HDBC.SqlValue

-- | Primitive query
hdbcPrimQuery :: GetRec er vr => 
		 Connection -- ^ Database connection.
	      -> String     -- ^ SQL query
	      -> Scheme     -- ^ List of field names to retrieve
	      -> Rel er     -- ^ Phantom argument to get the return type right.
	      -> IO [Record vr]    -- ^ Query results
hdbcPrimQuery conn sql scheme rel = 
    do
    stmt <- handleSqlError $ HDBC.prepare conn sql
    handleSqlError $ HDBC.execute stmt []
    rows <- HDBC.fetchAllRowsMap stmt
    mapM (getRec hdbcGetInstances rel scheme) rows

-- | Primitive execute
hdbcPrimExecute :: Connection -- ^ Database connection.
		-> String     -- ^ SQL query.
		-> IO ()
hdbcPrimExecute conn sql = 
    do
    handleSqlError $ HDBC.run conn sql []
    return ()


-----------------------------------------------------------
-- Getting data from a statement
-----------------------------------------------------------

hdbcGetInstances :: GetInstances HDBCRow
hdbcGetInstances = 
    GetInstances {
		  getString        = hdbcGetValue
		 , getInt          = hdbcGetValue
		 , getInteger      = hdbcGetValue
		 , getDouble       = hdbcGetValue
		 , getBool         = hdbcGetValue
		 , getCalendarTime = hdbcGetValue
		 }

hdbcGetValue :: SqlType a => HDBCRow -> String -> IO (Maybe a)
hdbcGetValue m f = case Map.lookup (map toLower f) m of
                     Nothing -> fail $ "No such field " ++ f
                     Just x  -> return $ HDBC.fromSql x
