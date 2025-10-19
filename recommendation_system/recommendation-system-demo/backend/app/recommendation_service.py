import pandas as pd
import numpy as np
from sklearn.metrics.pairwise import cosine_similarity
from sklearn.feature_extraction.text import TfidfVectorizer
from sqlalchemy.orm import Session
from . import models
import json
from typing import List, Dict

class RecommendationService:
    def __init__(self, db: Session, redis_client):
        self.db = db
        self.redis = redis_client
    
    def get_recommendations(self, user_id: int, algorithm: str = "hybrid") -> List[Dict]:
        if algorithm == "collaborative":
            return self.collaborative_filtering(user_id)
        elif algorithm == "content_based":
            return self.content_based_filtering(user_id)
        else:
            return self.hybrid_recommendations(user_id)
    
    def collaborative_filtering(self, user_id: int) -> List[Dict]:
        # Get user-item matrix
        interactions = self.db.query(models.Interaction).all()
        
        if not interactions:
            return []
        
        # Create user-item matrix
        user_item_matrix = {}
        for interaction in interactions:
            if interaction.user_id not in user_item_matrix:
                user_item_matrix[interaction.user_id] = {}
            user_item_matrix[interaction.user_id][interaction.item_id] = interaction.rating or 1.0
        
        if user_id not in user_item_matrix:
            return []
        
        # Find similar users
        target_user_ratings = user_item_matrix[user_id]
        similarities = {}
        
        for other_user_id, other_ratings in user_item_matrix.items():
            if other_user_id == user_id:
                continue
            
            # Calculate cosine similarity
            common_items = set(target_user_ratings.keys()) & set(other_ratings.keys())
            if len(common_items) < 2:
                continue
            
            vec1 = [target_user_ratings[item] for item in common_items]
            vec2 = [other_ratings[item] for item in common_items]
            
            if np.std(vec1) > 0 and np.std(vec2) > 0:
                similarity = cosine_similarity([vec1], [vec2])[0][0]
                similarities[other_user_id] = similarity
        
        # Get recommendations from similar users
        recommendations = {}
        for other_user_id, similarity in similarities.items():
            for item_id, rating in user_item_matrix[other_user_id].items():
                if item_id not in target_user_ratings:
                    if item_id not in recommendations:
                        recommendations[item_id] = 0
                    recommendations[item_id] += similarity * rating
        
        # Get top recommendations
        sorted_recs = sorted(recommendations.items(), key=lambda x: x[1], reverse=True)[:5]
        
        result = []
        for item_id, score in sorted_recs:
            item = self.db.query(models.Item).filter(models.Item.id == item_id).first()
            if item:
                result.append({
                    "item_id": item.id,
                    "title": item.title,
                    "category": item.category,
                    "score": round(score, 3),
                    "algorithm": "collaborative"
                })
        
        return result
    
    def content_based_filtering(self, user_id: int) -> List[Dict]:
        # Get user's interaction history
        user_interactions = self.db.query(models.Interaction).filter(
            models.Interaction.user_id == user_id
        ).all()
        
        if not user_interactions:
            return []
        
        # Get user's preferred categories
        preferred_categories = {}
        for interaction in user_interactions:
            item = self.db.query(models.Item).filter(models.Item.id == interaction.item_id).first()
            if item and item.category:
                if item.category not in preferred_categories:
                    preferred_categories[item.category] = 0
                preferred_categories[item.category] += interaction.rating or 1.0
        
        # Get all items not interacted with
        interacted_item_ids = [i.item_id for i in user_interactions]
        candidate_items = self.db.query(models.Item).filter(
            ~models.Item.id.in_(interacted_item_ids)
        ).all()
        
        recommendations = []
        for item in candidate_items:
            score = preferred_categories.get(item.category, 0)
            if score > 0:
                recommendations.append({
                    "item_id": item.id,
                    "title": item.title,
                    "category": item.category,
                    "score": round(score, 3),
                    "algorithm": "content_based"
                })
        
        return sorted(recommendations, key=lambda x: x["score"], reverse=True)[:5]
    
    def hybrid_recommendations(self, user_id: int) -> List[Dict]:
        collab_recs = self.collaborative_filtering(user_id)
        content_recs = self.content_based_filtering(user_id)
        
        # Combine recommendations with weights
        combined = {}
        
        for rec in collab_recs:
            combined[rec["item_id"]] = {
                **rec,
                "score": rec["score"] * 0.6,
                "algorithm": "hybrid"
            }
        
        for rec in content_recs:
            if rec["item_id"] in combined:
                combined[rec["item_id"]]["score"] += rec["score"] * 0.4
            else:
                combined[rec["item_id"]] = {
                    **rec,
                    "score": rec["score"] * 0.4,
                    "algorithm": "hybrid"
                }
        
        result = sorted(combined.values(), key=lambda x: x["score"], reverse=True)[:5]
        return result
