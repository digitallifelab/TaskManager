//
//  TaskEditViewController.swift
//  TaskManager
//
//  Created by CloudCraft on 1/19/16.
//  Copyright © 2016 CloudCraft. All rights reserved.
//

import UIKit
import CloudKit
import Eureka

class TaskEditViewController: FormViewController, TaskActionsViewDelegate {

    var taskBoard:Board?
    var creatorId:String?
    weak var weakTasksHolder:TasksHolder?
    private var currentTask:Task?
    
    var taskEditingType:TaskEditType = .CreateNew{
        didSet{
            switch taskEditingType{
                case .EditCurrent(let task):
                    self.currentTask = task
                    self.initialDetails = task.details!
                    self.initialTitle = task.title!
                    //self.boardRecordId = task.board?.recordId
                
                default:
                    break
            }
        }
    }
    
    var actionsHeader:HeaderFooterView<TaskActionsSectionTitleHeader> {
        
        let actionsTitle = NSLocalizedString("Action", comment: "")
        
        var header = HeaderFooterView<TaskActionsSectionTitleHeader>(.NibFile(name:"TaskActionsSectionTitleHeader", bundle:nil))
        
        header.onSetupView = {header, _, _ in
            
            header.titleLabel.text = actionsTitle
        }
        
        header.height = {30.0}
        
        return header
    }
    
    private var newTaskInfo:TempTaskInfo?
    
    private var initialTitle = ""
    private var initialDetails = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
        self.setupTableViewWithCurrentTask()
        switch taskEditingType
        {
            case .EditCurrent(_):
                self.setupTakeOrFinishButtonCell()
            default:
                break
        }
        
        self.creatorId = anAppDelegate()?.cloudKitHandler.publicCurrentUser?.recordID.recordName
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    //MARK: - 
    func setupTableViewWithCurrentTask()
    {
        let titleSectionTitle =  NSLocalizedString("Task title", comment:"")
        let detailsSectionTitle = NSLocalizedString("Task details", comment: "")
        let headerHeight = CGFloat(30.0)
        
        //prepare Title header
        var titleHeader = HeaderFooterView<TaskActionsSectionTitleHeader>(.NibFile(name:"TaskActionsSectionTitleHeader", bundle:nil))
        
        titleHeader.onSetupView = {titleHeader, _, _ in
            
            titleHeader.titleLabel.text = titleSectionTitle
        }
        
        titleHeader.height = {headerHeight}
        
        
        // prepare Details header
        var detailsHeader = HeaderFooterView<TaskActionsSectionTitleHeader>(.NibFile(name:"TaskActionsSectionTitleHeader", bundle:nil))
        
        detailsHeader.onSetupView = {header, _, _ in
            
            header.titleLabel.text = detailsSectionTitle
        }
        
        detailsHeader.height = {headerHeight}
        
        
        guard let task = self.currentTask else {
            
            form +++ Section(){ section in
            
                section.header = titleHeader
            }
                
                 <<< TextAreaRow(){
                        $0.placeholder = "enter task title"
                    
                    }.onChange{ [unowned self] (titlewRow) in
                        if let _ = self.newTaskInfo //update board title
                        {
                            self.newTaskInfo?.title = titlewRow.value ?? self.initialTitle
                            self.checkSaveButtonEnabled()
                        }
                        else
                        {
                            if let changedTitle = titlewRow.value,
                                let taskInfo = TempTaskInfo(boardRecord: self.taskBoard?.recordId),
                                let creator = self.creatorId
                            {
                                self.newTaskInfo = taskInfo
                                self.newTaskInfo?.setTitle(changedTitle)
                                self.newTaskInfo?.setCreator(creator)
                            }
                            self.checkSaveButtonEnabled()
                        }
                    }.cellSetup { (cell, row) -> () in
                        cell.textView.textContainerInset = UIEdgeInsetsMake(0, 50.0, 0, 0)
                    }
                
                +++ Section(){ section in
                    section.header = detailsHeader
                }
                <<< TextAreaRow() {
                        $0.placeholder = "enter task details"
                    }.onChange{ [unowned self] (detailsRow) in
                        if let _ = self.newTaskInfo //update board title
                        {
                            self.newTaskInfo?.setDetails(detailsRow.value ?? self.initialDetails)
                            self.checkSaveButtonEnabled()
                        }
                        else
                        {
                            if  let changedDetails = detailsRow.value,
                                let taskInfo = TempTaskInfo(boardRecord: self.taskBoard?.recordId),
                                let creatorId = self.creatorId
                                //let newTask = TaskInfo(taskBoardRecordId: boardRecId, creatorRecordId: creator, title: self.initialTitle, details: changedDetails)
                            {
                                self.newTaskInfo = taskInfo
                                self.newTaskInfo?.setDetails(changedDetails)
                                self.newTaskInfo?.setCreator(creatorId)
                            }

                            self.checkSaveButtonEnabled()
                        }
                    }
            return
        }
        
        form +++ Section(){ section in
           
                section.header = titleHeader
            }

            //add single cell in section
            <<< TextAreaRow() {
                    $0.value = task.title
                }.onChange{ [unowned self] (titlewRow) in
                   
                    self.currentTask?.title = titlewRow.value ?? self.initialTitle
                    self.checkSaveButtonEnabled()
                }.cellSetup { (cell, row) -> () in
                    cell.textView.textContainerInset = UIEdgeInsetsMake(0, 48.0, 0, 0)
                    cell.textView.font = UIFont.appSemiboldFontOfSize(28.0)
                    cell.height = { 80.0 }
            }
            
            +++ Section(){ section in
             
                section.header = detailsHeader
            }
            //add single cell in section
            <<< TextAreaRow() {
                    $0.value = task.details
                }.onChange{[unowned self] (detailsRow) in
                    
                    self.currentTask?.details = detailsRow.value ?? self.initialDetails
                    self.checkSaveButtonEnabled()
                }.cellSetup{ (cell, row) -> () in
                    cell.textView.textContainerInset = UIEdgeInsetsMake(0, 48.0, 0, 0)
                    cell.textView.font = UIFont.appRegularFontOfSize(14.0)
                    cell.textView.textColor = UIColor.grayColor()
                    
                }
    }
    
    
    
    
    //MARK: - Task Actions setup
    private func setupTakeOrFinishButtonCell()
    {
        setupActionsSection()
    }
    
    private func setupActionsSection() {
        
        guard let currentLoggedUserID = anAppDelegate()?.cloudKitHandler.publicCurrentUser?.recordID.recordName else {
            return
        }
        
        let actionsSection = Section(){ section in
            var footerView = HeaderFooterView<TaskActionsView>(.NibFile(name:"TaskActionsView", bundle:nil) )
            footerView.onSetupView = { view, section, formController in
                view.delegate = self
            }
            
            footerView.height = { 100.0 }
            
            section.footer = footerView
            
            section.header = actionsHeader
        }
       
         // 0 - Task title, 1 - Task details, 2 - Task actions(Take or Finish+Cancel)
        
        if currentTask?.dateFinished > 0 && currentTask?.dateTaken > 0{
            form[2] = actionsSection
            return
        }
        
        if let taskOwnerId = currentTask?.currentOwnerId where taskOwnerId == currentLoggedUserID {
            if currentTask?.dateFinished == 0{
                if currentTask?.dateTaken == 0{
                    form[2] = actionsSection
                }
                else{
                    form[2] = actionsSection
                }
            }
            else{
                form[2] = actionsSection
            }
        }
        else {
            
            form[2] = actionsSection
        }
    }
    
    private func setupFinishCancelButtons(section:Section) {
        
        let finishTaskButton = ButtonRow("Finish Task").cellSetup{(cell, row) in
                    cell.textLabel?.font = UIFont.boldSystemFontOfSize(17)
                    cell.tintColor = UIColor.blueColor()
                    row.title = "Finish"
                }.onCellSelection {[weak self] (cell, row) -> () in
                    cell.setSelected(false, animated: false)
                    self?.finishTaskPressed()
                }
        
        let cancelTaskButton = ButtonRow("Cancel Task").cellSetup(){ (cell, row) -> () in
                    cell.tintColor = UIColor.purpleColor()
                    row.title = "Cancel"
                }.onCellSelection(){[weak self] (cell, row) -> () in
                    cell.setSelected(false, animated: false)
                    self?.cancelTaskPressed()
                }
    
        section.removeAll()// in case there is Take button (Take button action)
        section[0] = finishTaskButton
        section[1] = cancelTaskButton
    }
//    
//    func setupDeleteSection()
//    {
//        let deleteButtonRow = ButtonRow().cellSetup(){ (cell, row) -> () in
//                cell.tintColor = UIColor.redColor()
//                row.title = "Delete"
//                }.onCellSelection {[weak self] (cell , _) -> () in
//                   
//                    cell.setSelected(false, animated: false)
//                    self?.deleteTaskPressed()
//                }
//
//        
//        form +++ Section("Danger Zone") <<<  deleteButtonRow
//    }
    
    //MARK: - Save  button
    private func checkSaveButtonEnabled()
    {
        
        switch taskEditingType
        {
            case .CreateNew:
                if let tempTask = self.newTaskInfo where !tempTask.title.isEmpty
                {
                    enableSaveButton()
                }
                else
                {
                    disableSaveButton()
                }
            case .EditCurrent(_):
                guard let task = self.currentTask else
                {
                    disableSaveButton()
                    return
                }
                
                if initialTitle == task.title && initialDetails == task.details
                {
                    disableSaveButton()
                }
                else if task.title == ""
                {
                    disableSaveButton() //there is no reason to create a task without at least a title
                }
                else //set SAVE button visible
                {
                    enableSaveButton()
                }
        }
        
    }
    
    private func enableSaveButton()
    {
        if self.navigationItem.rightBarButtonItem == nil
        {
            let saveBarButton = UIBarButtonItem(barButtonSystemItem: .Save, target: self, action: "saveEdits:")
            self.navigationItem.rightBarButtonItem = saveBarButton
        }
    }
    
    private func disableSaveButton()
    {
        self.navigationItem.rightBarButtonItem = nil
    }
    
    //MARK: - Cancel and Save nivigation button actions
    @IBAction func cancelBarButtonAction(sender:AnyObject?)
    {
        self.navigationController?.dismissViewControllerAnimated(true, completion: nil)
        return
    }
    
    func saveEdits(sender:UIBarButtonItem)
    {
        switch self.taskEditingType
        {
        case .EditCurrent( _ ):
            if let task = self.currentTask
            {
                self.weakTasksHolder?.editTask(task)
            }
            else
            {
                self.cancelBarButtonAction(nil)
            }
        case .CreateNew:
            if let taskInfo = self.newTaskInfo
            {
                self.weakTasksHolder?.insertNewTaskWithInfo(taskInfo)
                self.navigationController?.dismissViewControllerAnimated(true, completion: nil)
            }
            else
            {
                self.cancelBarButtonAction(nil)
            }
        }
    }
    
    //MARK: - Action buttons methods
    func deleteTaskPressed()
    {
        let action:AlertActionHandler = {[weak self] in
            guard let task = self?.currentTask, _ = anAppDelegate()?.cloudKitHandler.publicCurrentUser else
            {
                return
            }
            
            self?.weakTasksHolder?.deleteTask(task)
            self?.dismissViewControllerAnimated(true, completion: nil)
        }
        
        let alert = ActionController.alertWith("DELETE", actionButtonInfos: ["Delete" : action], dismissButtonTitle: "Cancel", hostViewController: self)
        
        alert.show()     
    }
    
    func takeTaskPressed()
    {
        guard let task = self.currentTask else
        {
            return
        }
        
        guard let publicUser = anAppDelegate()?.cloudKitHandler.publicCurrentUser else
        {
            return
        }        
        
        weakTasksHolder?.handleTakingTask(task, byUserID: publicUser.recordID.recordName)
        
        self.navigationController?.dismissViewControllerAnimated(true, completion: nil)
    }
    
    func finishTaskPressed() {
        
        guard let task = self.currentTask, let publicUserID = anAppDelegate()?.cloudKitHandler.publicCurrentUser?.recordID.recordName else {
            return
        }
        
        weakTasksHolder?.handleFinishingTask(task, byUserID: publicUserID)
        self.navigationController?.dismissViewControllerAnimated(true, completion: nil)
    }
    
    func cancelTaskPressed() {
        guard let task = self.currentTask, let userRecordId = anAppDelegate()?.cloudKitHandler.publicCurrentUser?.recordID.recordName else
        {
            return
        }

        weakTasksHolder?.handleCancellingTask(task, byUsedID: userRecordId)
        self.navigationController?.dismissViewControllerAnimated(true, completion: nil)
    }
    
    //MARK: - TaskActionsViewDelegate
    func taskActionButtonTapped(button: UIView?) {
        //scroll button to center
        if let button = button{
            
            
            let currentCenter = CGRectGetMidY(self.view.frame)
            let currentPosition = button.convertPoint(button.center, toView: self.view)
            
            let difference = floor(currentPosition.y - currentCenter)
            
            if difference < 0.0{
            
                return
            }
            
            self.tableView?.contentInset = UIEdgeInsetsMake(0, 0, difference, 0)
            
            if let footer = form[2].footer, let actionsView = footer.viewForSection(form[2], type: HeaderFooterType.Footer, controller: self) {
                
                let frame = actionsView.frame
                self.tableView?.scrollRectToVisible(frame, animated: true)
            }
        }
    }
    
    override func scrollViewWillBeginDragging(scrollView:UIScrollView){
        super.scrollViewWillBeginDragging(scrollView)
        UIView.animateWithDuration(0.2) {
            self.tableView!.contentInset = UIEdgeInsetsZero
        }
    }
    
}
