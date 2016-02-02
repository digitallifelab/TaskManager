//
//  CloudKitDatabaseHandler.swift
//  TaskCloud
//
//  Created by CloudCraft on 1/11/16.
//  Copyright © 2016 CloudCraft. All rights reserved.
//

import Foundation
import CloudKit
import UIKit

let noUserError = NSError(domain: "No Logged User", code: -1, userInfo: [NSLocalizedDescriptionKey:"No current user found"])
let unknownError = NSError(domain: "UnknownError", code: -16, userInfo: [NSLocalizedDescriptionKey:"No error from CloudKit  recieved"])

class CloudKitDatabaseHandler{
    
    private let container: CKContainer
    private let publicDB:  CKDatabase
    private let privateDB: CKDatabase
    
    private var currentUserRecord:CKRecord?
    
    var currentUserPhoneNumber:String?{
        didSet{
            print("new phone number is set in cloudKitDatabaseHandler")
        }
    }
    
    private lazy var pCurrentUserAvatar = UIImage()
    
    var currentUserAvatar:UIImage?{
        
        if let recordID = anAppDelegate()?.cloudKitHandler.currentUserPhoneNumber
        {
            if self.pCurrentUserAvatar.size == CGSizeZero
            {
                if let image = DocumentsFolderFileHandler().getAvatarImageFromDocumentsForUserId(recordID)
                {
                    self.pCurrentUserAvatar = image
                    return self.pCurrentUserAvatar
                }
                return nil
            }
            else
            {
                return self.pCurrentUserAvatar
            }
        }
        return nil
    }
    
    lazy var privateOperationQueue = NSOperationQueue()
    
    init() {
        self.container = CKContainer.defaultContainer()
        self.publicDB = container.publicCloudDatabase
        self.privateDB = container.privateCloudDatabase
    }

    var publicCurrentUser:CKRecord?{
        return self.currentUserRecord
    }
    
    func checkAccountStatus(completion:(status:CKAccountStatus, error:NSError?)->())
    {
        self.container.accountStatusWithCompletionHandler { (accStatus, lvError) in
            if let anError = lvError
            {
                print(anError)
                completion(status: accStatus, error:  anError)
            }
            else
            {
                completion(status: accStatus, error: nil)
            }
        }
    }
    
    /**
     calls **statusForApplicationPermission: completion:** to check *UserDiscoverability*
     */
    func checkPermissions(completion:(status:CKApplicationPermissionStatus, error:NSError?)->())
    {
        self.container.statusForApplicationPermission(CKApplicationPermissions.UserDiscoverability) { (permissionStatus, error) in
            if let anError = error
            {
                completion(status:permissionStatus, error: anError)
            }
            else
            {
                completion(status: permissionStatus, error: nil)
            }
        }
    }
    //MARK: - Subscriptions
    func queryAllSubscriptions(completion:((subscriptions:[CKSubscription]?)->()))
    {
        let fetchCompletionBlock:(([String : CKSubscription]?, NSError?) -> Void) = {subscriptions, error in
            let result = CloudKitErrorParser.handleCloudKitErrorAs(error)
            switch result
            {
                case .Success:
                    if let subs = subscriptions where !subs.isEmpty
                    {
                        var toReturn = [CKSubscription]()
                        for (_,value) in subs
                        {
                            toReturn.append(value)
                        }
                        completion(subscriptions: toReturn)
                    }
                    else
                    {
                        completion(subscriptions: nil)
                    }
                case .Retry(let afterSeconds):
                    if afterSeconds < 5
                    {
                        print("retrying to fetch all subscriptions")
                        let timeout:dispatch_time_t = dispatch_time(DISPATCH_TIME_NOW, Int64(Double(NSEC_PER_SEC) * afterSeconds))
                        dispatch_after(timeout, dispatch_get_main_queue()){ () -> Void in
                            self.queryAllSubscriptions(completion)
                        }
                    }
                    else
                    {
                        completion(subscriptions: nil)
                    }
                case .RecoverableError:
                    completion(subscriptions: nil)
                case .Fail(_):
                    completion(subscriptions: nil)
            }
        }
        
        let allSubsOp = CKFetchSubscriptionsOperation.fetchAllSubscriptionsOperation()
        allSubsOp.qualityOfService = .Utility
        allSubsOp.fetchSubscriptionCompletionBlock = fetchCompletionBlock
        
        self.publicDB.addOperation(allSubsOp)
    }
    
    func deleteSubscriptions(toDelete:[String], completion:((deletedIDs:[String]?)->()))
    {
        if toDelete.isEmpty
        {
            completion(deletedIDs: nil)
            return
        }
        
        let completionBlock : (([CKSubscription]?, [String]?, NSError?) -> Void) = {_, deletedIDs, error in
            if let successDeleted = deletedIDs
            {
                completion(deletedIDs: successDeleted)
                return
            }
            
            completion(deletedIDs: nil)
        }
        
        let modifyToDeleteOp = CKModifySubscriptionsOperation(subscriptionsToSave: nil, subscriptionIDsToDelete: toDelete)
        modifyToDeleteOp.qualityOfService = .Utility
        modifyToDeleteOp.modifySubscriptionsCompletionBlock = completionBlock
        
        self.publicDB.addOperation(modifyToDeleteOp)
    }
    
    func submitSubscription(subscription:CKSubscription, completion:((subscription:CKSubscription?, errorMessage:String?)->()) )
    {
        networkingIndicator(true)
//        publicDB.saveSubscription(subscription) { (savedSubscription, error) -> Void in
//            
//            let result = CloudKitErrorParser.handleCloudKitErrorAs(error, retryAttempt: 10.0)
//            switch result
//            {
//            case .Success:
//                if let savedSubscription = savedSubscription
//                {
//                    completion(subscription:savedSubscription, errorMessage:nil)
//                }
//                else
//                {
//                    completion(subscription: nil, errorMessage: "Empty succeeded subscriptions")
//                }
//                
//            case .Fail(let message):
//                completion(subscription: nil, errorMessage: message)
//                
//            case .Retry(let afterSeconds):
//                
//                if afterSeconds < 10
//                {
//                    let timeout:dispatch_time_t = dispatch_time(DISPATCH_TIME_NOW, Int64(Double(NSEC_PER_SEC) * afterSeconds))
//                    dispatch_after(timeout, dispatch_get_main_queue()){ () -> Void in
//                        self.submitSubscription(subscription, completion: completion)
//                    }
//                }
//                else
//                {
//                    completion(subscription: nil, errorMessage: "failed to subscript after timeout")
//                }
//                
//            case .RecoverableError:
//                completion(subscription: nil, errorMessage: "Try later")
//            }
//
//            
//            networkingIndicator(false)
//        }
//        
//        return
        
        let completionBlock : (([CKSubscription]?, [String]?, NSError?) -> Void) = {newSubscriptions, _ , error in
            let result = CloudKitErrorParser.handleCloudKitErrorAs(error, retryAttempt: 10.0)
            switch result
            {
                case .Success:
                    if let savedSubscriptions = newSubscriptions where !savedSubscriptions.isEmpty
                    {
                        completion(subscription:savedSubscriptions.first!, errorMessage:nil)
                    }
                    else
                    {
                        completion(subscription: nil, errorMessage: "Empty succeeded subscriptions")
                    }
                
                case .Fail(let message):
                    completion(subscription: nil, errorMessage: message)
                
                case .Retry(let afterSeconds):
                 
                    if afterSeconds < 10
                    {
                        let timeout:dispatch_time_t = dispatch_time(DISPATCH_TIME_NOW, Int64(Double(NSEC_PER_SEC) * afterSeconds))
                        dispatch_after(timeout, dispatch_get_main_queue()){ () -> Void in
                            self.submitSubscription(subscription, completion: completion)
                        }
                    }
                    else
                    {
                        completion(subscription: nil, errorMessage: "failed to subscript after timeout")
                    }
                
                case .RecoverableError:
                    completion(subscription: nil, errorMessage: "Try later")
            }
            networkingIndicator(false)
        }
        
        let modifyToInsertOp = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
        modifyToInsertOp.qualityOfService = .Utility
        modifyToInsertOp.modifySubscriptionsCompletionBlock = completionBlock
        
        networkingIndicator(true)
        publicDB.addOperation(modifyToInsertOp)
    }
    
    //MARK: - Notifications
    func sendNotidicationsRead(ids:[CKNotificationID], completion:((marked:[CKNotificationID], error:NSError?)->()) )
    {
        if ids.isEmpty
        {
            completion(marked: ids, error: nil)
            return
        }
        
        let completionBlock:(([CKNotificationID]?, NSError?) -> Void) = {succeededIDs, error in
            networkingIndicator(false)
            let result = CloudKitErrorParser.handleCloudKitErrorAs(error)
            switch result
            {
            case .Success:
                if let noteIDs = succeededIDs where noteIDs.isEmpty
                {
                    completion(marked: noteIDs, error: nil)
                }
                else
                {
                    completion(marked: [CKNotificationID](), error: nil)
                }
            default:
                completion(marked: [CKNotificationID](), error: error)
            }
        }
        
        let didReadOperation = CKMarkNotificationsReadOperation(notificationIDsToMarkRead: ids)
        didReadOperation.qualityOfService = .Utility
        didReadOperation.markNotificationsReadCompletionBlock = completionBlock
        
        networkingIndicator(true)
        NSOperationQueue().addOperation(didReadOperation)
    }
    
    //MARK: - syncing stuff
    func requestChanges( completion:(notifications:[CKQueryNotification])->() )
    {
        print("\n Cloud Kit handler requestChanges.....")
        
        var totalNotesRecieved = [CKQueryNotification]()
        
        var proceed = false
        
        repeat
        {
            let result = self.requestMoreChanges()
            proceed = result.moreComing
            
            if let notifs = result.changes
            {
                totalNotesRecieved += notifs
            }
        }
        while proceed == true
        
        completion(notifications: totalNotesRecieved)
    }
    
    private func requestMoreChanges() -> (moreComing:Bool, changes:[CKQueryNotification]?)
    {
        var optionalToken:CKServerChangeToken?
        
        if let optionalTokenData = UserDefaultsManager.getCloudKitChangeToken(), let token = NSKeyedUnarchiver.unarchiveObjectWithData(optionalTokenData) as? CKServerChangeToken
        {
            optionalToken = token
        }
        
        var optionalChangeNotifications:[CKQueryNotification]?
        
        let changesOp = CKFetchNotificationChangesOperation(previousServerChangeToken: optionalToken)
        
        var result:(moreComing:Bool, changes:[CKQueryNotification]?) = (moreComing:false, changes:nil)
        
        let perNoteCompletionBlock:((CKNotification) -> ()) = { note in
            if let queryNote = note as? CKQueryNotification
            {
                if var optionalChangeNotifications = optionalChangeNotifications
                {
                    optionalChangeNotifications.append(queryNote)
                }
                else
                {
                    optionalChangeNotifications = [CKQueryNotification]()
                    optionalChangeNotifications!.append(queryNote)
                }
            }
            else
            {
                
            }
        }
        
        let totalCompletion:((CKServerChangeToken?, NSError?) ->()) = {changesToken, error in
            
            
            if changesOp.moreComing{
                result.moreComing = true
            }
            
            if let newToken = changesToken
            {
                let tokenData = NSKeyedArchiver.archivedDataWithRootObject(newToken)
                UserDefaultsManager.setCloudKitChangeToken(tokenData)
            }
            print("Cloud kit handler fetchNotificationChangesCompletionBlock  fired\n")
        }
        
        
        changesOp.fetchNotificationChangesCompletionBlock = totalCompletion
        changesOp.notificationChangedBlock = perNoteCompletionBlock
        changesOp.qualityOfService = .UserInitiated
        
        privateOperationQueue.addOperations([changesOp], waitUntilFinished: true)
        print("Cloud kit handler did finish requesting changes\n")
        
        return result
    }
    
    //MARK: - current User
    func queryForLoggedUserByPhoneNumber(phoneNumber:String, completion:((currentUserRecord:CKRecord?, error:NSError?)->()))
    {
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
    
        let userRecordID = CKRecordID(recordName: phoneNumber)
        publicDB.fetchRecordWithID(userRecordID) {[weak self] (foundUser, errorFetch) -> Void in
            
            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
            
            let result = CloudKitErrorParser.handleCloudKitErrorAs(errorFetch, retryAttempt: 2.0)
            switch result
            {
                case .Retry(let afterSeconds):
                    print("Retrying to query existing user by phone number ID...")
                    print("Retry interval: \(afterSeconds) \n")
                case .Fail(let message):
                    if let _ = message
                    {
                        completion(currentUserRecord: nil, error: NSError(domain: "User Login Failure", code: -31, userInfo: [NSLocalizedFailureReasonErrorKey: message!]))
                    }
                    else
                    {
                        completion(currentUserRecord: nil, error: unknownError)
                    }
                case .RecoverableError:
                    completion(currentUserRecord: nil, error: unknownError)
                case .Success:
                    guard let existingUser = foundUser else
                    {
                        self?.currentUserRecord = nil
                        if let anError = errorFetch
                        {
                            //let ckMessageError = anError[CKErrorCode]
                            NSLog("- Error whine querying logged user by phone number:\n %@", anError.description)
                        }
                        else
                        {
                            completion(currentUserRecord: nil, error: unknownError)
                        }
                        return
                    }
                    //NSLog(" - CloudKitDatabaseHandler - Did found user in public DB: \n -recordId: %@\n -recordType: %@\n -phoneNumberField: %@\n", existingUser.recordID, existingUser.recordType, (existingUser["phoneID"] as? String) ?? "Not Found")
                    self?.currentUserRecord = existingUser
                    completion(currentUserRecord: existingUser, error: nil)
            }
        }
    }
    
    func insertNewPublicUserIntoCloudByPhoneNumber(phoneNumber:String, completion:((successUser:CKRecord?, error:NSError?)->()))
    {
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
        
        let userRecordId = CKRecordID(recordName: phoneNumber)
        let newRecord = CKRecord(recordType: "PublicUser", recordID: userRecordId)
        newRecord["phoneID"] = phoneNumber
        
        publicDB.saveRecord(newRecord) {[weak self] (userSaved, errorSaving) -> Void in
            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
            
            if let anError = errorSaving
            {
                NSLog(" - Error while saving new PublicUser into iCloud:\n%@", anError)
                completion(successUser: nil, error: anError)
            }
            else if let user = userSaved
            {
                NSLog(" - Did save new PublicUser into iCloud with phone number: %@ ", phoneNumber)
                self?.currentUserRecord = user
                completion(successUser: user, error: nil)
            }
            else
            {
                NSLog(" - Did not recieve any saved user or error while \"saveRecord:\"  called")
                completion(successUser: nil, error: NSError(domain: "FetchNone", code: -14, userInfo: [NSLocalizedDescriptionKey:"Recieved empty response in completion block"]))
            }
        }
    }
    
    /**
     - Parameter phones: anarray of phone number strings to check for registered users
     - Parameter completion: completion handler after request finishes
     - Precondition: **phones** should not be empty, or the methow returns immediately with empty parameters
     */
    func startFetchingForRegisteredUsersByPhoneNumbers(phones:[String], completion:((foundNumbers:[String], error:NSError?)->()) )
    {
        if phones.isEmpty
        {
            completion(foundNumbers: [String](), error: nil)
            return
        }
        
        let completionBlock = { (recordInfo:[CKRecordID : CKRecord]?, error:NSError?) in
            
            let errorResult = CloudKitErrorParser.handleCloudKitErrorAs(error)
            switch errorResult
            {
                case .Success, .RecoverableError: //RecoverableError happens, when some PublicUser records found but not all
                    var numbersToReturn:[String]?
                    if let recInfo = recordInfo
                    {
                        var foundRecordIDs = [String]()
                        for ( _ , value) in recInfo
                        {
                            //print(key)
                            //print(":")
                            //print(value.recordID.recordName)
                            foundRecordIDs.append(value.recordID.recordName)
                        }
                        
                        numbersToReturn = foundRecordIDs
                    }
                    
                    if let _ = numbersToReturn
                    {//return emptyresponse
                        completion(foundNumbers: numbersToReturn!, error: nil)
                    }
                    else
                    {//return empty response
                        completion(foundNumbers: [String](), error: nil)
                    }                
                default:
                    print(errorResult)
                    completion(foundNumbers: [String()], error: error)
            }
        }
        
        var recordIDs = [CKRecordID]()
        for aPhone in phones
        {
            recordIDs.append( CKRecordID(recordName: aPhone) )
        }
        
        let findOperation = CKFetchRecordsOperation(recordIDs: recordIDs)
        
        findOperation.qualityOfService = .Utility

        findOperation.fetchRecordsCompletionBlock = completionBlock
        
        self.publicDB.addOperation(findOperation)
    }
    
    //MARK: - Boards
    func queryForBoardsByCurrentUser(completion:((boards:[CKRecord]?, error:NSError?)->()))
    {
        guard let user = self.publicCurrentUser else
        {
            completion(boards: nil, error: noUserError)
            return
        }
        
        let predicate = NSPredicate(format: "boardCreator = %@", user.recordID.recordName)
        let publicQuery = CKQuery(recordType: CloudRecordTypes.TaskBoard.rawValue, predicate: predicate)
        publicQuery.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: true)]
        
        publicDB.performQuery(publicQuery, inZoneWithID: nil) { (foundBoardRecords, queryError) -> Void in
            guard let error = queryError else
            {
                NSLog(" - Found user boards: %ld", foundBoardRecords!.count)
                completion(boards: foundBoardRecords, error: nil)
                return
            }
            NSLog(" - Error while querying user boards: \n%@", error.userInfo)
            completion(boards: nil, error: error)
        }
    }
    
    func queryForBoardsSharedWithMe(completion:((boards:[CKRecord]?, fetchError:NSError?)->()))
    {
        guard let user = self.publicCurrentUser else
        {
            completion(boards: nil, fetchError: noUserError)
            return
        }
        
        let predicate = NSPredicate(format: "SELF.participants CONTAINS %@", user.recordID.recordName)
        let publicQuery = CKQuery(recordType: CloudRecordTypes.TaskBoard.rawValue, predicate: predicate)
        publicQuery.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: true)]
        
        publicDB.performQuery(publicQuery, inZoneWithID: nil) { (sharedBoardRecords, fetchError) in
            let result = CloudKitErrorParser.handleCloudKitErrorAs(fetchError)
            switch result
            {
                case .Success, .RecoverableError:
                    completion(boards: sharedBoardRecords, fetchError: nil)
                case .Retry(let afterSeconds):
                    let timeout:dispatch_time_t = dispatch_time(DISPATCH_TIME_NOW, Int64(Double(NSEC_PER_SEC) * afterSeconds))
                    dispatch_after(timeout, dispatch_get_main_queue()) { _ in
                        self.queryForBoardsSharedWithMe(completion)
                    }
                case .Fail(let message):
                    completion(boards: nil, fetchError: NSError(domain: fetchError!.domain, code: fetchError!.code, userInfo: [NSLocalizedFailureReasonErrorKey:message ?? "no error reason"]))
                
            }
        }
    }
    
    func submitNewBoardWithInfo(boardInfo:TaskBoardInfo, completion:((createdBoard:CKRecord?, error:NSError?)->()))
    {
        guard let currentUser = publicCurrentUser else
        {
            completion(createdBoard: nil, error: noUserError)
            return
        }
     
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true

        let newBoardRecord = createNewBoardRecordFromInfo(boardInfo, creatorId: currentUser.recordID)
        
        publicDB.saveRecord(newBoardRecord) { (savedNewBoard, saveError) -> Void in
            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
            
            guard let newBoard = savedNewBoard else
            {
                if let anError = saveError
                {
                    completion(createdBoard: nil, error: anError)
                }
                else
                {
                    completion(createdBoard: nil, error:unknownError)
                }
                return
            }
            completion(createdBoard: newBoard, error: nil)
        }
    }
    
    func editBoard(boardInfo:TaskBoardInfo, completion:((editedRecord:CKRecord?, editError:NSError?)->()))
    {
        guard let recordId = boardInfo.recordId else
        {
            completion(editedRecord: nil, editError: noBoardIdError)
            return
        }
    
        //fetch if there is existing board
        publicDB.fetchRecordWithID(recordId) {[unowned self] (foundRecord, error) -> Void in
            if let foundBoard = foundRecord
            {
                //let boardToUpdate = foundBoard
                foundBoard[SortOrderIndexIntKey] = NSNumber(integer: boardInfo.sortOrderIndex)
                foundBoard[BoardTitleKey] = boardInfo.title
                foundBoard[BoardDetailsKey] = boardInfo.details
                foundBoard[BoardParticipantsKey] = boardInfo.participants
                
                self.saveBoard(foundBoard) { (savedBoard, saveError) -> () in
                    completion(editedRecord: savedBoard, editError: saveError)
                }
            }
            else
            {
                self.submitNewBoardWithInfo(boardInfo) { (createdBoard, errorCreatingNewBoard) -> () in
                    completion(editedRecord: createdBoard, editError: errorCreatingNewBoard)
                }
            }
        }
    }
    
    func deleteBoardWithID(recordId:CKRecordID, completion:((deletedRecordId:CKRecordID?, error:NSError?)->()))
    {
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
        publicDB.deleteRecordWithID(recordId) { (deletedRecordId, deletionError) -> Void in
            
            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
            guard let dbError = deletionError else
            {
                NSLog(" - Deleted user Board SUCCESS")
                completion(deletedRecordId: deletedRecordId, error: nil)
                return
            }
            
            NSLog(" - Error while deleting user TaskBoard: \n%@", dbError.userInfo.description)
            completion(deletedRecordId: nil, error: dbError)
        }
    }
    
    func findBoardWithID(recordIDString:String, completion:((boardRecord:CKRecord?)->()))
    {
        
    }
    
    private func saveBoard(board:CKRecord, completionHandler:((savedBoard:CKRecord?, saveError:NSError?)->()))
    {
        self.publicDB.saveRecord(board) { (recordSaved, errorSaving) -> Void in
            completionHandler(savedBoard: recordSaved, saveError: errorSaving)
        }
    }
    
    //MARK: - Tasks
    func loadTasksForBoardId(boardId:CKRecordID, completion:((tasks:[TaskInfo]?, error:ErrorType?)->()))
    {
        let referenceForBoard = CKReference(recordID: boardId, action: .DeleteSelf)
        let predicate = NSPredicate(format: "board = %@", referenceForBoard)
        let tasksForBoard = CKQuery(recordType: CloudRecordTypes.Task.rawValue, predicate: predicate)
        
        publicDB.performQuery(tasksForBoard, inZoneWithID: nil) { (recordsFound, recordsQueryError) -> Void in
            
            let errorParsingResult = CloudKitErrorParser.handleCloudKitErrorAs(recordsQueryError)
           
            switch errorParsingResult{
            case .Success:
                if let taskRecords = recordsFound
                {
                    NSLog(" DID load tasks for board: %ld", taskRecords.count)
                    
                    var taskInfos = [TaskInfo]()
                    for aRecord in taskRecords
                    {
                        guard let _ = aRecord[TaskCreatorReferenceKey] as? CKReference else
                        {
                            print("Could not create task info from CKRecord: task creator reference not found...")
                            continue
                        }
                        
                        guard let taskInfo = taskInfoFromTaskRecord(aRecord) else
                        {
                            print("Could not create task info from CKRecord : returned nil from constructor function")
                            continue
                        }
                        
                        taskInfos.append(taskInfo)
                    }
                    
                    completion(tasks: taskInfos, error: nil)
                }
            default:
                if let anError = recordsQueryError
                {
                    NSLog(" - An error fetching tasks by board:\n%@", anError)
                    completion(tasks: nil, error: anError)
                    return
                }
            }
        }
    }
    
    func submitTask(taskInfo:TaskInfo, completion:((taskRecord:CKRecord?, savingError:NSError?)->()))
    {
        guard let user = self.currentUserRecord else
        {
            completion(taskRecord: nil, savingError: UserError.NotFound as NSError)
            return
        }
        
        if user.recordID.recordName != taskInfo.creatorId.recordName
        {
            completion(taskRecord: nil, savingError: UserError.CreatorRecordIdMismatch as NSError)
            return
        }
        
        let newTaskRecord = createNewTaskRecordFromInfo(taskInfo)
        
     
        publicDB.saveRecord(newTaskRecord) { (savedRecord, savingError) in
            if let record = savedRecord
            {
                completion(taskRecord: record, savingError: nil)
            }
            else if let error = savingError
            {
                NSLog(" - Error submitting new TASK record to iCloud: \n %@", error)
                completion(taskRecord: nil, savingError: error)
            }
        }
        
    }
    
    func editTask(taskInfo:TaskInfo, completion:((editedRecord:CKRecord?, editError:NSError?)->()))
    {
        //0 declare editing workflow 
        
        let editRecord:(record:CKRecord, editingInfo:TaskInfo)->() = {[weak self] (var record:CKRecord, taskInfo:TaskInfo) in
            
            record[TitleStringKey] = taskInfo.title
            record[DetailsStringKey] = taskInfo.details
            record[SortOrderIndexIntKey] = taskInfo.sortOrderIndex
            updateOwnerForTaskRecord(&record, ownerId: taskInfo.currentOwner, dates:(taskInfo.dateTaken , taskInfo.dateFinished))
            
            self?.publicDB.saveRecord(record) { (savedRecord, saveError)  in
                completion(editedRecord: savedRecord, editError: saveError)
            }
        }
        
        //1 finc record to edit
        if let taskRecordId = taskInfo.recordId
        {
            self.publicDB.fetchRecordWithID(taskRecordId) { (foundRecord, fetchError) in
                if let existingTaskRecord = foundRecord
                {
                    editRecord(record: existingTaskRecord, editingInfo: taskInfo)
                }
                else
                {
                    self.submitTask(taskInfo) { (taskRecord, savingError) -> () in
                        completion(editedRecord: taskRecord, editError: savingError)
                    }
                }
            }
        }
        else
        {
            completion(editedRecord: nil, editError: NSError(domain: "TaskEditing", code: -2, userInfo: [NSLocalizedFailureReasonErrorKey:"Task recordID was not found", NSLocalizedDescriptionKey:"Could not edit task. Internal error."]))
        }
    }
    
    func deleteTask(taskInfo:TaskInfo, completion:((deletedId:CKRecordID?, deletionError:NSError?)->()))
    {
        if let recordID = taskInfo.recordId
        {
            publicDB.deleteRecordWithID(recordID) { (deletedRecordID, deletionError) in
                
                completion(deletedId: deletedRecordID, deletionError: deletionError)
            }
        }
        else
        {
            completion(deletedId: nil, deletionError: NSError(domain: "TaskEditing", code: -2, userInfo: [NSLocalizedFailureReasonErrorKey:"Task recordID was not found", NSLocalizedDescriptionKey:"Could not edit task. Internal error."]))
        }
    }
    
}//class end


//MARK: - Helpers
func createNewTaskRecordFromInfo(taskInfo:TaskInfo) -> CKRecord
{
    let newTaskRecord = CKRecord(recordType: CloudRecordTypes.Task.rawValue)
    
    let userReference = CKReference(recordID: taskInfo.creatorId, action: .None)
    let boardReference = CKReference(recordID: taskInfo.taskBoardId , action: .DeleteSelf)
    newTaskRecord[TaskCreatorReferenceKey] = userReference //not optional
    newTaskRecord[BoardReferenceKey] = boardReference // not optional
    newTaskRecord[TitleStringKey] = taskInfo.title //not optional
    
    newTaskRecord[DetailsStringKey] = taskInfo.details //non optional but can be empty string
    newTaskRecord[SortOrderIndexIntKey] =  NSNumber(integer:  taskInfo.sortOrderIndex) // not optional , ZERO by default
    newTaskRecord[CurrentOwnerStringKey] = taskInfo.currentOwner // optional
    newTaskRecord[DateTakenDateKey] = taskInfo.dateTaken //optional
    newTaskRecord[DateFinishedDateKey] = taskInfo.dateFinished //optional
    
    return newTaskRecord
}

func createNewBoardRecordFromInfo(boardInfo:TaskBoardInfo, creatorId:CKRecordID) -> CKRecord
{
    let newBoardRecord = CKRecord(recordType: CloudRecordTypes.TaskBoard.rawValue)
    newBoardRecord[BoardCreatorIDKey] = creatorId.recordName
    newBoardRecord[BoardTitleKey] = boardInfo.title
    newBoardRecord[BoardDetailsKey] = boardInfo.details
    newBoardRecord[SortOrderIndexIntKey] = NSNumber(integer: boardInfo.sortOrderIndex)
    newBoardRecord[BoardParticipantsKey] = boardInfo.participants
    
    return newBoardRecord
}

func taskInfoFromTaskRecord(record:CKRecord) -> TaskInfo?
{
    guard let creatorIdRef = record[TaskCreatorReferenceKey] as? CKReference else
    {
        return nil
    }
    
    guard let taskTitle = record[TitleStringKey] as? String else
    {
        return nil
    }
    
    let optionalDetails = record[DetailsStringKey] as? String
    
    guard var newTask = TaskInfo(taskBoardRecordId: record.recordID, creatorRecordId: creatorIdRef.recordID, title: taskTitle, details: optionalDetails) else
    {
        return nil
    }
    
    newTask.setRecordId(record.recordID)
    newTask.fillOptionalInfoFromTaskRecord(record)
  
    return newTask
}

func updateOwnerForTaskRecord(inout record:CKRecord, ownerId:String?, dates:(taken:NSDate?, finished:NSDate?))
{
    record[CurrentOwnerStringKey] = ownerId
    record[DateTakenDateKey] = dates.0
    record[DateFinishedDateKey] = dates.1
}

