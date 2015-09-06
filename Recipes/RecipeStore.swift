//
//  RecipeStore.swift
//  Recipes
//
//  Created by Nofel Mahmood on 29/08/2015.
//  Copyright © 2015 Hyper. All rights reserved.
//

import Foundation
import CoreData


let RecipeStoreAttributeServerNameKey = "serverName"

let RecipeEntityName = "Recipe"
let PhotoEntityName = "Photo"
let InstructionEntityName = "Instruction"

let RecipeEntityIDAttributeName = "id"
let RecipeEntityPhotoRelationshipName = "photo"
let RecipeEntityInstructionsRelationshipName = "instructions"

let InstructionEntityIDAttributeName = "id"
let InstructionEntityNameAttributeName = "name"

enum RecipeStoreError: ErrorType {
  case InvalidEntity
}

let RecipeStoreDidSaveSuccessfulNotification = "RecipeStoreDidSaveSuccessfulNotification"
let RecipeStoreDidSaveUnSuccessfulNotification = "RecipeStoreDidSaveUnSuccessfulNotification"

class RecipeStore: NSIncrementalStore
{
  var cache = [NSNumber: [String: AnyObject]]()
  
  class var type:String {
    return NSStringFromClass(self)
  }
  
  override class func initialize() {
    NSPersistentStoreCoordinator.registerStoreClass(self, forStoreType: self.type)
  }
  
  override func loadMetadata() throws {
    self.metadata=[
      NSStoreUUIDKey: NSProcessInfo().globallyUniqueString,
      NSStoreTypeKey: self.dynamicType.type
    ]
  }
  
  // MARK: Requests
  override func executeRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext?) throws -> AnyObject {
    
    if let context = context {
      if request is NSFetchRequest {
        return self.executeInResponseToFetchRequest(request as! NSFetchRequest, withContext: context)
      } else if request is NSSaveChangesRequest {
        return self.executeInResponseToSaveChangesRequest(request as! NSSaveChangesRequest, withContext: context)
      }
    }
    return []
  }
  
  func executeInResponseToFetchRequest(request: NSFetchRequest, withContext context: NSManagedObjectContext) -> [NSManagedObject] {
    
    if let entityName = request.entityName where entityName == RecipeEntityName {
      if let recipesKeyValues = RecipeApi.sharedAPI.recipes() {
        var fetchedObjects = [NSManagedObject]()
        let transformer = RecipeKeyValueTransformer(recipeEntity: request.entity!)
        for recipeKeyValue in recipesKeyValues {
          if let id = recipeKeyValue[RecipeEntityIDAttributeName] as? NSNumber {
            if let transformedValue = transformer.transformedValue(recipeKeyValue) as? [String: NSObject] {
              self.cache[id] = transformedValue
              let managedObjectID = self.newObjectIDForEntity(request.entity!, referenceObject: id)
              let managedObject = context.objectWithID(managedObjectID)
              fetchedObjects.append(managedObject)
            }
          }
        }
        return fetchedObjects
      }
    }
    return []
  }
  
  func executeInResponseToSaveChangesRequest(request: NSSaveChangesRequest, withContext context: NSManagedObjectContext) -> [NSManagedObjectContext] {
    
    if let recipeEntity = context.persistentStoreCoordinator?.managedObjectModel.entitiesByName[RecipeEntityName] {
      let transformer = RecipeKeyValueTransformer(recipeEntity: recipeEntity)
      let insertedRecipe = request.insertedObjects?.filter {
        return $0 is Recipe
      }.first as? Recipe
      let deletedRecipe = request.deletedObjects?.filter {
        return $0 is Recipe
      }.first as? Recipe
      let updatedRecipe = request.updatedObjects?.filter {
        return $0 is Recipe
      }.first as? Recipe
      
      if let insertedRecipe = insertedRecipe {
        if let recipeParameters = transformer.reverseTransformedValue(insertedRecipe.dictionaryWithValuesForKeys(Array(insertedRecipe.entity.propertiesByName.keys))) as? [String: AnyObject] {
          RecipeApi.sharedAPI.createOrUpdate(withRecipeID: nil, usingRecipeParameters: recipeParameters, photoData: nil, completionBlock: { (error) -> Void in
            if error == nil {
              NSOperationQueue.mainQueue().addOperationWithBlock {
                NSNotificationCenter.defaultCenter().postNotificationName(RecipeStoreDidSaveSuccessfulNotification, object: context)
              }
            } else {
              NSOperationQueue.mainQueue().addOperationWithBlock {
                NSNotificationCenter.defaultCenter().postNotificationName(RecipeStoreDidSaveUnSuccessfulNotification, object: context)
              }
            }
          })
        }
      } else if let deletedRecipeID = deletedRecipe?.id?.integerValue {
        RecipeApi.sharedAPI.delete(deletedRecipeID, completionBlock: { (error) -> Void in
          if error == nil {
            NSOperationQueue.mainQueue().addOperationWithBlock {
              NSNotificationCenter.defaultCenter().postNotificationName(RecipeStoreDidSaveSuccessfulNotification, object: context)
            }
          } else {
            NSOperationQueue.mainQueue().addOperationWithBlock {
              NSNotificationCenter.defaultCenter().postNotificationName(RecipeStoreDidSaveUnSuccessfulNotification, object: context)
            }
          }
        })
      } else if let updatedRecipe = updatedRecipe {
        if let recipeID = updatedRecipe.id?.integerValue, let recipeParameters = transformer.reverseTransformedValue(updatedRecipe.dictionaryWithValuesForKeys(Array(updatedRecipe.entity.propertiesByName.keys))) as? [String: AnyObject] {
          RecipeApi.sharedAPI.createOrUpdate(withRecipeID: recipeID, usingRecipeParameters: recipeParameters, photoData: nil, completionBlock: { (error) -> Void in
            if error == nil {
              NSOperationQueue.mainQueue().addOperationWithBlock {
                NSNotificationCenter.defaultCenter().postNotificationName(RecipeStoreDidSaveSuccessfulNotification, object: context)
              }
            } else {
              NSOperationQueue.mainQueue().addOperationWithBlock {
                NSNotificationCenter.defaultCenter().postNotificationName(RecipeStoreDidSaveUnSuccessfulNotification, object: context)
              }
            }
          })
        }
      }
    }
    
    return []
  }
  
  // MARK: Faulting
  override func newValuesForObjectWithID(objectID: NSManagedObjectID, withContext context: NSManagedObjectContext) throws -> NSIncrementalStoreNode {
    
    if let entityName = objectID.entity.name {
      if entityName == RecipeEntityName {
        if let recipeID = self.referenceObjectForObjectID(objectID) as? NSNumber {
          if let cachedValue = self.cache[recipeID] {
            let propertiesByServerName = objectID.entity.propertiesByServerName
            var incrementalStoreNodeValues = [String: AnyObject]()
            for (_,property) in propertiesByServerName {
              if let attributeDescription = property as? NSAttributeDescription {
                if let valueForKey = cachedValue[attributeDescription.name] {
                  incrementalStoreNodeValues[attributeDescription.name] = valueForKey
                }
              } else if let relationshipDescription = property as? NSRelationshipDescription {
                if relationshipDescription.toMany {
                  continue
                }
                if let destinationEntity = relationshipDescription.destinationEntity, let id = cachedValue[RecipeEntityIDAttributeName] as? NSNumber {
                  let relationshipObjectID = self.newObjectIDForEntity(destinationEntity, referenceObject: id)
                  incrementalStoreNodeValues[relationshipDescription.name] = relationshipObjectID
                }
              }
            }
            return NSIncrementalStoreNode(objectID: objectID, withValues: incrementalStoreNodeValues, version: 0)
          }
        }
      } else if entityName == PhotoEntityName, let photoID = self.referenceObjectForObjectID(objectID) as? NSNumber {
        if let cachedValue = self.cache[photoID] {
          if let photoCachedValue = cachedValue[RecipeEntityPhotoRelationshipName] as? [String: AnyObject] {
            return NSIncrementalStoreNode(objectID: objectID, withValues: photoCachedValue, version: 0)
          }
        }
      } else if entityName == InstructionEntityName {
        if let referenceObject = (self.referenceObjectForObjectID(objectID) as? String)?.componentsSeparatedByString(RecipeInstructionsSeparator) {
          if  referenceObject.count == 2 {
            let recipeID = NSNumber(integer: (referenceObject[0] as NSString).integerValue)
            let instructionID = (referenceObject[1] as NSString).integerValue
            if let cachedValue = self.cache[recipeID] {
              if let instructions = cachedValue[RecipeEntityInstructionsRelationshipName] as? [Int: String] {
                var incrementalStoreNodeValues = [String: AnyObject]()
                incrementalStoreNodeValues[InstructionEntityNameAttributeName] = instructions[instructionID]
                incrementalStoreNodeValues[InstructionEntityIDAttributeName] = instructionID
                return NSIncrementalStoreNode(objectID: objectID, withValues: incrementalStoreNodeValues, version: 0)
              }
            }
          }
        }
      }
    }
    throw RecipeStoreError.InvalidEntity
  }
  
  override func newValueForRelationship(relationship: NSRelationshipDescription, forObjectWithID objectID: NSManagedObjectID, withContext context: NSManagedObjectContext?) throws -> AnyObject {
    
    if let entityName = relationship.destinationEntity?.name {
      if entityName == InstructionEntityName {
        if let recipeID = self.referenceObjectForObjectID(objectID) as? NSNumber {
          if let cachedValue = self.cache[recipeID] {
            if let instructionsValue = cachedValue[RecipeEntityInstructionsRelationshipName] as? [Int: String] {
              var objectIDs = [NSManagedObjectID]()
              for (key, _) in instructionsValue {
                let referenceObject = "\(recipeID.integerValue)\(RecipeInstructionsSeparator)\(key)"
                let objectID = self.newObjectIDForEntity(relationship.destinationEntity!, referenceObject: referenceObject)
                objectIDs.append(objectID)
              }
              return objectIDs
            }
          }
        }
      }
    }
    throw RecipeStoreError.InvalidEntity
  }
}
