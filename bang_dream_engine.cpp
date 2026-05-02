#include <iostream>
#include <vector>
#include <string>
#include <functional>
#include <map>
#include <ctime>
#include <cstdlib>
#include <algorithm>
#include <iomanip>

using namespace std;

// --- Data Structures ---

class Band;

class Venue {
public:
    string name;
    string city;
    Band* owner;
    Venue(string n, string c) : name(n), city(c), owner(nullptr) {}
};

class Member {
public:
    string name;
    string part;
    int perf, stam, hp, max_hp, xp;

    Member(string n, string p, int pr, int st) 
        : name(n), part(p), perf(pr), stam(st), max_hp(100), hp(100), xp(0) {}

    void train() {
        perf += 5;
        stam += 3;
        max_hp += 10;
        hp = max_hp;
        cout << ">> " << name << " (" << part << ") stats increased!\n";
    }
};

class Band {
public:
    string name;
    vector<Member> members;
    vector<Venue*> venues;
    map<string, string> relations;

    Band(string n, vector<Member> m) : name(n), members(m) {}

    void addVenue(Venue* v) { v->owner = this; venues.push_back(v); }
    void removeVenue(Venue* v) {
        auto it = find(venues.begin(), venues.end(), v);
        if (it != venues.end()) venues.erase(it);
    }
    void addMember(string n, string p, int pr, int st) {
        Member newMusician(n, p, pr, st);
        members.push_back(newMusician);
        cout << "[SYSTEM] " << n << " (" << p << ") has been added to " << this->name << "!" << endl;
    }
    void removeMember(string mName) {
        auto it = remove_if(members.begin(), members.end(), [&](const Member& m) { return m.name == mName; });
        if (it != members.end()) members.erase(it, members.end());
    }
};

// 1. FORWARD DECLARATION (The fix!)
class GameEngine; 

// --- Game Engine ---
struct Event {
    string id;
    string description;
    bool triggered = false;
    
    // Condition: Should this happen?
    std::function<bool(int turn, const vector<Band>& bands)> condition;
    
    // Action: What happens? (Passes reference to engine to modify state)
    std::function<void(GameEngine& engine)> action;

    Event(string name, string desc, 
          std::function<bool(int, const vector<Band>&)> cond,
          std::function<void(GameEngine&)> act)
        : id(name), description(desc), condition(cond), action(act) {}
};

class GameEngine {
private:
    vector<Band> bands;
    vector<Venue> worldMap;
    Band* player = nullptr;
    int turn = 1;
    vector<Event> eventPool;

public:
    GameEngine() {
        srand(time(0));
        
        // 1. Setup Expanded Map (8 Venues)
        worldMap.push_back(Venue("CiRCLE", "Tokyo"));
        worldMap.push_back(Venue("Galaxy", "Shinjuku"));
        worldMap.push_back(Venue("7th!", "Shibuya"));
        worldMap.push_back(Venue("Dub", "West Tokyo"));
        worldMap.push_back(Venue("Space", "Kita-Senju"));
        worldMap.push_back(Venue("KID BOX", "Nagoya"));
        worldMap.push_back(Venue("V-HALL", "Osaka"));
        worldMap.push_back(Venue("Drum Be-1", "Fukuoka"));

        // 2. Setup Full Band Members (5 per band)
        bands.reserve(10);
        bands.push_back(Band("Poppin'Party", {
            {"Kasumi", "Vo/Gt", 25, 20}, {"Otae", "Gt", 30, 15}, {"Rimi", "Ba", 18, 25}, {"Saaya", "Dr", 22, 22}, {"Arisa", "Key", 20, 20}
        }));
        bands.push_back(Band("Roselia", {
            {"Yukina", "Vo", 35, 12}, {"Sayo", "Gt", 32, 18}, {"Lisa", "Ba", 20, 28}, {"Ako", "Dr", 18, 22}, {"Rinko", "Key", 22, 25}
        }));
        bands.push_back(Band("Afterglow", {
            {"Ran", "Vo/Gt", 28, 18}, {"Moca", "Gt", 26, 18}, {"Himari", "Ba", 20, 25}, {"Tomoe", "Dr", 25, 25}, {"Tsugumi", "Key", 18, 28}
        }));
        bands.push_back(Band("Pastel*Palettes", {
            {"Aya", "Vo", 22, 22}, {"Hina", "Gt", 30, 15}, {"Chisato", "Ba", 22, 28}, {"Maya", "Dr", 24, 24}, {"Eve", "Key", 18, 25}
        }));

        // 3. Initial Territory Assignment (2 Venues per band)
        for(int i=0; i<4; ++i) {
            bands[i].addVenue(&worldMap[i*2]);
            bands[i].addVenue(&worldMap[i*2 + 1]);
            for(int j=0; j<4; ++j) if(i != j) bands[i].relations[bands[j].name] = "Neutral";
        }
        setupEvents();
    }
// --- The new, ultra-clean executeEvent ---
    void executeEvent(Event& ev) {
        cout << "\n[!] STORY EVENT: " << ev.description << endl;
        if (ev.action) {
            ev.action(*this); // "Hey event, do your thing to this engine"
        }
    }

    void setupEvents() {
        // Example: RAS_RAID
        eventPool.emplace_back(
            "RAS_RAID", 
            "RAISE A SUILEN disrupts the peace!",
            [](int t, const vector<Band>& b) { return t == 3; },
            [](GameEngine& eng) {
                Band* popipa = eng.findBand("Poppin'Party");
                if (popipa) {
                    popipa->removeMember("Otae");
                    
                    // Create RAS
                    Band ras("RAISE A SUILEN", {});
                    ras.addMember("CHU2", "Prod", 45, 10);
                    ras.addMember("Otae", "Gt", 40, 25);
                    
                    eng.bands.push_back(ras);
                    
                    // Set Relations
                    eng.setRelations("Poppin'Party", "RAISE A SUILEN", "Rival");
                }
            }
        );

        // Example: FRIENDSHIP_PACT
        eventPool.emplace_back(
            "FRIENDSHIP", 
            "Roselia and Poppin'Party find common ground.",
            [](int t, const vector<Band>& b) { return t >= 5; },
            [](GameEngine& eng) {
                eng.setRelations("Poppin'Party", "Roselia", "Allied");
            }
        );
    }

    // Helper to keep code clean
    void setRelations(string b1, string b2, string status) {
        Band* band1 = findBand(b1);
        Band* band2 = findBand(b2);
        if (band1 && band2) {
            band1->relations[b2] = status;
            band2->relations[b1] = status;
            cout << ">> " << b1 << " and " << b2 << " are now " << status << "!" << endl;
        }
    }
    Band* findBand(string name) {
        for (auto& b : bands) if (b.name == name) return &b;
        return nullptr;
    }

    void endTurn() {
        turn++;
        processEvents();
    }


    void checkMemberStatus() {
        cout << "\n--- " << player->name << " MEMBER ROSTER ---\n";
        cout << left << setw(12) << "Name" << setw(10) << "Part" << setw(8) << "PERF" << setw(8) << "STAM" << "HP" << endl;
        cout << "---------------------------------------------\n";
        for (auto& m : player->members) {
            cout << left << setw(12) << m.name << setw(10) << m.part << setw(8) << m.perf 
                 << setw(8) << m.stam << m.hp << "/" << m.max_hp << endl;
        }
    }

    void trainMembers() {
        cout << "\nSelect a member to train (Costs 1 Turn):\n";
        for (int i=0; i<player->members.size(); ++i) {
            cout << i+1 << ". " << player->members[i].name << endl;
        }
        int choice; cin >> choice;
        player->members[choice-1].train();
    }

	void handleBattle(Band* attacker, Band* defender, Venue* v) {
        cout << "\n==================================================" << endl;
        cout << "  LIVE BATTLE: " << attacker->name << " vs " << defender->name << endl;
        cout << "  LOCATION: " << v->name << endl;
        cout << "==================================================\n" << endl;

        // Iterators to track which member is currently on stage
        int aIdx = 0; 
        int dIdx = 0;

        // Battle continues as long as both bands have at least one member with HP
        while (aIdx < attacker->members.size() && dIdx < defender->members.size()) {
            Member& aM = attacker->members[aIdx];
            Member& dM = defender->members[dIdx];

            cout << ">>> CURRENT MATCHUP: " << aM.name << " vs " << dM.name << " <<<" << endl;

            while (aM.hp > 0 && dM.hp > 0) {
                // Attacker Member strikes
                int dmgToD = max(8, (aM.perf / 2) - (dM.stam / 4) + rand() % 15);
                dM.hp -= dmgToD;
                cout << "[INVADER] " << aM.name << " performs! " << dM.name << " HP: " << max(0, dM.hp) << endl;

                if (dM.hp <= 0) {
                    cout << ">> " << dM.name << " is exhausted and leaves the stage! <<" << endl;
                    dIdx++; // Defender brings out next member
                    break;
                }

                // Defender Member strikes back
                int dmgToA = max(8, (dM.perf / 2) - (aM.stam / 4) + rand() % 15);
                aM.hp -= dmgToA;
                cout << "[DEFENDER] " << dM.name << " replies! " << aM.name << " HP: " << max(0, aM.hp) << endl;

                if (aM.hp <= 0) {
                    cout << ">> " << aM.name << " is exhausted and leaves the stage! <<" << endl;
                    aIdx++; // Attacker brings out next member
                    break;
                }
                
                cout << "--------------------------------------------------" << endl;
            }
        }

        // --- Final Result Logic ---
        cout << "\n==================================================" << endl;
        if (aIdx < attacker->members.size()) {
            cout << "  RESULT: VICTORY! " << attacker->name << " cleared the stage!" << endl;
            cout << "  " << attacker->members.size() - aIdx << " members still standing." << endl;
            defender->removeVenue(v);
            attacker->addVenue(v);
        } else {
            cout << "  RESULT: DEFEAT... " << defender->name << " defended the venue!" << endl;
            cout << "  " << defender->members.size() - dIdx << " members still standing." << endl;
        }
        cout << "==================================================\n" << endl;

        // Reset all members' HP for the next turn/battle
        auto resetHP = [](Band* b) {
            for (auto& m : b->members) m.hp = m.max_hp;
        };
        resetHP(attacker);
        resetHP(defender);
    }

    void processEvents() {
        for (auto& ev : eventPool) {
            // 1. Skip if already done
            if (ev.triggered) continue;
    
            // 2. Check the condition (passing turn and current bands)
            // This runs the lambda logic we defined in setupEvents()
            if (ev.condition(turn, bands)) {
                executeEvent(ev);
                ev.triggered = true; // Ensure it only fires once
            }
        }
    }

    // --- The Modified Run Loop ---
    void run() {
        cout << "=== BanG Dream! Conquest Engine ===\n";
        cout << "Select your Band:\n";
        for(int i=0; i<4; ++i) cout << i+1 << ". " << bands[i].name << endl;
        int choice; cin >> choice; player = &bands[choice-1];
        bands.push_back(Band("RAISE A SUILEN", {}));
        Band& ras = bands.back();
        bool gaming = true;
        while (gaming) {
            // 1. Process Flexible Story Events
            processEvents();

            // 2. Display HUD
            cout << "\n==========================================" << endl;
            cout << " TURN: " << turn << " | BAND: " << player->name << endl;
            cout << " VENUES HELD: " << player->venues.size() << endl;
            cout << "==========================================" << endl;

            cout << "1. View Map & Relations\n";
            cout << "2. Member Status & Training\n";
            cout << "3. Diplomacy (Set Rivalry)\n";
            cout << "4. INVADE (Gauntlet Battle)\n";
            cout << "5. Recruit New Member\n";
            cout << "6. End Turn\n";
            cout << "7. Quit\n";
            cout << "Choice: ";
            int act; cin >> act;

            switch (act) {
                case 1: // View Map
                    for (auto& v : worldMap) {
                        string rel = (v.owner == player) ? "YOU" : player->relations[v.owner->name];
                        cout << "- " << v.name << " | Owner: " << v.owner->name << " [" << rel << "]\n";
                    }
                    break;

                case 2: // Status & Training
                    checkMemberStatus();
                    cout << "Train a member? (y/n): ";
                    char t; cin >> t;
                    if (t == 'y') trainMembers();
                    break;

                case 3: // Diplomacy
                    setDiplomacy();
                    break;

                case 4: // INVADE
                    startInvasion();
                    break;

                case 5: // Recruit
                    recruitMember();
                    break;

                case 6:
                    turn++;
                    cout << "Passing the day...\n";
                    break;

                case 7:
                    gaming = false;
                    break;
            }

            // Check Win/Loss conditions
            if (player->venues.empty()) {
                cout << "\nYour band has no venues left to play. Game Over.\n";
                gaming = false;
            } else if (player->venues.size() == worldMap.size()) {
                cout << "\nYou have conquered the entire Japanese music scene!\n";
                gaming = false;
            }
        }
    }

    // --- Sub-routines for Run ---

    void startInvasion() {
        vector<Venue*> targets;
        for (auto& v : worldMap) {
            if (v.owner != player && player->relations[v.owner->name] == "Rival") {
                targets.push_back(&v);
            }
        }

        if (targets.empty()) {
            cout << "No Rivals available to invade. Use Diplomacy first!\n";
            return;
        }

        for (int i=0; i<targets.size(); ++i) {
            cout << i+1 << ". " << targets[i]->name << " (" << targets[i]->owner->name << ")\n";
        }
        int t; cin >> t;
        handleBattle(player, targets[t-1]->owner, targets[t-1]);
        turn++; // Invasion ends the turn
    }

    void recruitMember() {
        string n, p;
        cout << "Enter Recruit Name: "; cin >> n;
        cout << "Enter Part: "; cin >> p;
        player->addMember(n, p, 20, 20);
        turn++;
    }

    void setDiplomacy() {
    cout << "\n--- DIPLOMACY OFFICE ---" << endl;
    
    // 1. Filter out the player's own band
    vector<Band*> otherBands;
    for (auto& b : bands) {
        if (b.name != player->name) {
            otherBands.push_back(&b);
        }
    }

    if (otherBands.empty()) {
        cout << "No other bands found in the scene." << endl;
        return;
    }

    // 2. Display current relations
    cout << "Select a band to change relations:" << endl;
    for (int i = 0; i < otherBands.size(); ++i) {
        string currentRel = player->relations[otherBands[i]->name];
        if (currentRel == "") currentRel = "Neutral";
        cout << i + 1 << ". " << otherBands[i]->name << " (Current: " << currentRel << ")" << endl;
    }

    int choice;
    cout << "Choice: ";
    cin >> choice;

    if (choice < 1 || choice > otherBands.size()) {
        cout << "Invalid selection." << endl;
        return;
    }

    Band* target = otherBands[choice - 1];

    // 3. Select New Stance
    cout << "\nChoose new stance for " << target->name << ":" << endl;
    cout << "1. Declare Rival (Allows Invasion)" << endl;
    cout << "2. Propose Alliance (Requires 'Neutral' or better)" << endl;
    cout << "3. Reset to Neutral" << endl;
    int stance;
    cin >> stance;

    if (stance == 1) {
        player->relations[target->name] = "Rival";
        target->relations[player->name] = "Rival"; // Rivalry is mutual
        cout << "!!! War declared! You can now invade " << target->name << "'s venues." << endl;
    } 
    else if (stance == 2) {
        // Simple logic: Can't ally if currently rivals without a plot event
        if (player->relations[target->name] == "Rival") {
            cout << "[!] They hate you too much! You must wait for a story event to befriend a Rival." << endl;
        } else {
            player->relations[target->name] = "Allied";
            target->relations[player->name] = "Allied";
            cout << ">> You are now Allies! Your fanbases will merge for bigger shows." << endl;
        }
    } 
    else {
        player->relations[target->name] = "Neutral";
        target->relations[player->name] = "Neutral";
        cout << "Relations normalized." << endl;
    }
}
    
};

int main() { GameEngine().run(); return 0; }