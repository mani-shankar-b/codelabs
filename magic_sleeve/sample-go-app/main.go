package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"
)

type Item struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Value int    `json:"value"`
}

type Store struct {
	items map[string]Item
	mu    sync.RWMutex
}

var store = &Store{
	items: make(map[string]Item),
}

func main() {
	// Initialize with some sample data
	store.mu.Lock()
	store.items["1"] = Item{ID: "1", Name: "Item One", Value: 100}
	store.items["2"] = Item{ID: "2", Name: "Item Two", Value: 200}
	store.items["3"] = Item{ID: "3", Name: "Item Three", Value: 300}
	store.mu.Unlock()

	http.HandleFunc("/", healthHandler)
	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/items", itemsHandler)
	http.HandleFunc("/items/", itemHandler)
	http.HandleFunc("/api/items", itemsAPIHandler)
	http.HandleFunc("/api/items/", itemAPIHandler)

	port := ":8080"
	log.Printf("Server starting on port %s", port)
	log.Printf("Health check: http://localhost%s/health", port)
	log.Printf("Get all items: http://localhost%s/items", port)
	log.Printf("Get item by ID: http://localhost%s/items/1", port)
	
	if err := http.ListenAndServe(port, nil); err != nil {
		log.Fatal("Server failed to start:", err)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":    "healthy",
		"timestamp": time.Now().Format(time.RFC3339),
		"service":   "simple-go-app",
	})
}

func itemsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	store.mu.RLock()
	items := make([]Item, 0, len(store.items))
	for _, item := range store.items {
		items = append(items, item)
	}
	store.mu.RUnlock()
	json.NewEncoder(w).Encode(items)
}

func itemHandler(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Path[len("/items/"):]
	store.mu.RLock()
	item, exists := store.items[id]
	store.mu.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	if !exists {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "Item not found"})
		return
	}
	json.NewEncoder(w).Encode(item)
}

func itemsAPIHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		itemsHandler(w, r)
	case http.MethodPost:
		var item Item
		if err := json.NewDecoder(r.Body).Decode(&item); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(map[string]string{"error": "Invalid JSON"})
			return
		}
		store.mu.Lock()
		if item.ID == "" {
			item.ID = fmt.Sprintf("%d", len(store.items)+1)
		}
		store.items[item.ID] = item
		store.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(item)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func itemAPIHandler(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Path[len("/api/items/"):]
	
	switch r.Method {
	case http.MethodGet:
		store.mu.RLock()
		item, exists := store.items[id]
		store.mu.RUnlock()
		w.Header().Set("Content-Type", "application/json")
		if !exists {
			w.WriteHeader(http.StatusNotFound)
			json.NewEncoder(w).Encode(map[string]string{"error": "Item not found"})
			return
		}
		json.NewEncoder(w).Encode(item)
		
	case http.MethodPut:
		var item Item
		if err := json.NewDecoder(r.Body).Decode(&item); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(map[string]string{"error": "Invalid JSON"})
			return
		}
		item.ID = id
		store.mu.Lock()
		store.items[id] = item
		store.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(item)
		
	case http.MethodDelete:
		store.mu.Lock()
		_, exists := store.items[id]
		if exists {
			delete(store.items, id)
		}
		store.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		if !exists {
			w.WriteHeader(http.StatusNotFound)
			json.NewEncoder(w).Encode(map[string]string{"error": "Item not found"})
			return
		}
		json.NewEncoder(w).Encode(map[string]string{"message": "Item deleted"})
		
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

