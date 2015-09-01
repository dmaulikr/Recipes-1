//
//  Recipe.swift
//  Recipes
//
//  Created by Nofel Mahmood on 30/08/2015.
//  Copyright © 2015 Hyper. All rights reserved.
//

import Foundation
import CoreData

enum RecipeDifficultyDescription: Int {
  case Easy = 1
  case Medium = 2
  case Hard = 3
}

class Recipe: NSManagedObject {
  
  // Insert code here to add functionality to your managed object subclass
  var instructionsList: [String]? {
    return self.instructions?.componentsSeparatedByString(",").filter {
      return !$0.isEmpty
    }
  }
  
  func difficultyDescription() -> String {
    return "\(RecipeDifficultyDescription(rawValue: self.difficulty!.integerValue)!)"
  }
  
}
