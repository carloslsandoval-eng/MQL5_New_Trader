//+------------------------------------------------------------------+
//|                                                    CNetwork.mqh |
//|                                  Copyright 2024, Carlos Sandoval |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Carlos Sandoval"
#property link      ""
#property strict

//+------------------------------------------------------------------+
//| CNetwork Class                                                    |
//| Architecture: Recurrent Constructive (NEAT-style)                |
//| Type: Standalone. No Dependencies.                               |
//| Style: Telegraphic. Fast Math.                                   |
//+------------------------------------------------------------------+

// ==========================================
// Enums and Constants
// ==========================================
enum ENUM_NODE_TYPE
{
   NODE_INPUT,
   NODE_HIDDEN,
   NODE_OUTPUT
};

enum ENUM_ACTIVATION
{
   ACT_SIGMOID,
   ACT_TANH
};

// Output Layer Fixed Indices (0-5)
#define IDX_BUY  0   // Act: Sigmoid
#define IDX_SELL 1   // Act: Sigmoid
#define IDX_FILT 2   // Act: Sigmoid (Gatekeeper > 0.5)
#define IDX_SL   3   // Act: Sigmoid (Ratio 0.0-1.0)
#define IDX_TP   4   // Act: Sigmoid (Ratio 0.0-1.0)
#define IDX_SIZE 5   // Act: Sigmoid (Vol Mult 0.0-1.0)

#define CNT_OUT  6
#define MAX_NODES 50 // Cap to prevent CPU blowout

// ==========================================
// Structures
// ==========================================
struct SNode
{
   int               id;
   ENUM_NODE_TYPE    type;
   double            bias;
   double            response;
   ENUM_ACTIVATION   activation;
   double            value;        // Current activation value
   double            sum;          // Accumulated input sum
};

struct SLink
{
   int               in_node_id;
   int               out_node_id;
   double            weight;
   bool              enabled;
   bool              recurrent;
};

//+------------------------------------------------------------------+
//| CNetwork Class                                                    |
//+------------------------------------------------------------------+
class CNetwork
{
private:
   SNode             m_nodes[];
   SLink             m_links[];
   int               m_input_count;
   int               m_node_counter;
   
   // Private helper math
   double            Sigmoid(double x);
   double            Tanh(double x);
   double            RandomRange(double min, double max);
   
   // Network topology helpers
   int               FindNodeIndex(int node_id);
   bool              LinkExists(int in_id, int out_id);
   void              AddNode(ENUM_NODE_TYPE type, ENUM_ACTIVATION act);
   void              AddLink(int in_id, int out_id, double weight);
   
public:
   // Constructor/Destructor
                     CNetwork();
                    ~CNetwork();
   
   // Initialization
   bool              Init_Genesis(int input_count);
   
   // Runtime
   bool              FeedForward(double &inputs[], double &outputs[]);
   
   // Evolution
   void              Mutate();
   void              Mutate_AddNode();
   void              Mutate_AddLink();
   void              Mutate_PerturbWeights();
   
   // Getters
   int               GetNodeCount() { return ArraySize(m_nodes); }
   int               GetLinkCount() { return ArraySize(m_links); }
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CNetwork::CNetwork()
{
   m_input_count = 0;
   m_node_counter = 0;
   ArrayResize(m_nodes, 0);
   ArrayResize(m_links, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CNetwork::~CNetwork()
{
   ArrayFree(m_nodes);
   ArrayFree(m_links);
}

//+------------------------------------------------------------------+
//| Genesis Initialization (Heuristic Sparse)                        |
//| Input Map: [0]PA, [1]ATR, [2]DistHi, [3]VolSlope                |
//+------------------------------------------------------------------+
bool CNetwork::Init_Genesis(int input_count)
{
   if(input_count < 4)
   {
      Print("ERROR: Minimum 4 inputs required for heuristic mapping");
      return false;
   }
   
   m_input_count = input_count;
   m_node_counter = 0;
   
   // Clear existing network
   ArrayResize(m_nodes, 0);
   ArrayResize(m_links, 0);
   
   // 1. Create Output Nodes (0-5)
   for(int i = 0; i < CNT_OUT; i++)
   {
      AddNode(NODE_OUTPUT, ACT_SIGMOID);
   }
   
   // 2. Wire "The Eyes to the Brain" (Heuristic Map)
   
   // Direction (Buy/Sell) sees Price Action [0]
   AddLink(0, IDX_BUY,  RandomRange(-1.0, 1.0));
   AddLink(0, IDX_SELL, RandomRange(-1.0, 1.0));
   
   // Filter sees Ceiling Proximity [2] (Constraint)
   AddLink(2, IDX_FILT, RandomRange(-1.0, 1.0));
   
   // Risk (SL/TP) sees Volatility Regime [1]
   AddLink(1, IDX_SL, RandomRange(0.5, 1.0));  // Bias positive
   AddLink(1, IDX_TP, RandomRange(0.5, 1.0));  // Bias positive
   
   // Sizing sees Volatility Acceleration [3]
   AddLink(3, IDX_SIZE, RandomRange(-1.0, 1.0));
   
   return true;
}

//+------------------------------------------------------------------+
//| FeedForward - Process inputs through network                     |
//+------------------------------------------------------------------+
bool CNetwork::FeedForward(double &inputs[], double &outputs[])
{
   int input_size = ArraySize(inputs);
   if(input_size < m_input_count)
   {
      Print("ERROR: Not enough inputs. Expected ", m_input_count, " got ", input_size);
      return false;
   }
   
   int node_count = ArraySize(m_nodes);
   
   // 1. Reset node states
   for(int i = 0; i < node_count; i++)
   {
      m_nodes[i].value = 0.0;
      m_nodes[i].sum = m_nodes[i].bias;
   }
   
   // 2. Process through network (iterative passes for recurrent support)
   // Simple approach: Multiple passes to allow signal propagation
   int max_iterations = 3;  // Enough for shallow networks
   
   for(int iter = 0; iter < max_iterations; iter++)
   {
      int link_count = ArraySize(m_links);
      
      for(int i = 0; i < link_count; i++)
      {
         if(!m_links[i].enabled)
            continue;
         
         int in_id = m_links[i].in_node_id;
         int out_id = m_links[i].out_node_id;
         double weight = m_links[i].weight;
         
         // Get input value
         double in_value = 0.0;
         
         // Check if input node
         if(in_id < m_input_count)
         {
            in_value = inputs[in_id];
         }
         else
         {
            // Hidden or output node
            int node_idx = FindNodeIndex(in_id);
            if(node_idx >= 0)
               in_value = m_nodes[node_idx].value;
         }
         
         // Accumulate to output node
         int out_idx = FindNodeIndex(out_id);
         if(out_idx >= 0)
         {
            m_nodes[out_idx].sum += in_value * weight;
         }
      }
      
      // 3. Activate all nodes
      for(int i = 0; i < node_count; i++)
      {
         double sum = m_nodes[i].sum * m_nodes[i].response;
         
         // Apply activation based on type
         if(m_nodes[i].type == NODE_HIDDEN)
         {
            if(m_nodes[i].activation == ACT_TANH)
               m_nodes[i].value = Tanh(sum);
            else
               m_nodes[i].value = Sigmoid(sum);
         }
         else if(m_nodes[i].type == NODE_OUTPUT)
         {
            // Outputs always use Sigmoid [0.0, 1.0]
            m_nodes[i].value = Sigmoid(sum);
         }
      }
   }
   
   // 4. Extract outputs (first 6 nodes are outputs)
   ArrayResize(outputs, CNT_OUT);
   for(int i = 0; i < CNT_OUT; i++)
   {
      outputs[i] = m_nodes[i].value;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Mutate - Probabilistic dispatcher                                |
//+------------------------------------------------------------------+
void CNetwork::Mutate()
{
   double rnd = RandomRange(0.0, 1.0);
   
   if(rnd < 0.05)
   {
      Mutate_AddNode();
   }
   else if(rnd < 0.10)
   {
      Mutate_AddLink();
   }
   else if(rnd < 0.90)  // 0.80 -> 0.90 to ensure weight mutations happen
   {
      Mutate_PerturbWeights();
   }
}

//+------------------------------------------------------------------+
//| Mutate_AddNode - Split link with new hidden node                 |
//| Preserves flow: A->C becomes A->B->C                             |
//+------------------------------------------------------------------+
void CNetwork::Mutate_AddNode()
{
   int link_count = ArraySize(m_links);
   if(link_count == 0)
      return;
   
   // Check if we're at capacity
   if(ArraySize(m_nodes) >= MAX_NODES)
      return;
   
   // Pick random enabled link
   int attempts = 0;
   int link_idx = -1;
   
   while(attempts < 20)
   {
      link_idx = (int)(RandomRange(0, link_count - 0.001));
      if(m_links[link_idx].enabled)
         break;
      attempts++;
   }
   
   if(attempts >= 20 || link_idx < 0)
      return;
   
   // Disable old link
   m_links[link_idx].enabled = false;
   
   int in_id = m_links[link_idx].in_node_id;
   int out_id = m_links[link_idx].out_node_id;
   double old_weight = m_links[link_idx].weight;
   
   // Create new hidden node
   int new_node_id = m_node_counter;
   AddNode(NODE_HIDDEN, ACT_TANH);
   
   // Create two new links: in->new and new->out
   // Preserve flow by using weight=1.0 and old_weight
   AddLink(in_id, new_node_id, 1.0);
   AddLink(new_node_id, out_id, old_weight);
}

//+------------------------------------------------------------------+
//| Mutate_AddLink - Connect unconnected nodes (no duplicates)       |
//+------------------------------------------------------------------+
void CNetwork::Mutate_AddLink()
{
   int node_count = ArraySize(m_nodes);
   if(node_count == 0)
      return;
   
   // Try to find valid connection (limited attempts)
   int attempts = 0;
   int max_attempts = 30;
   
   while(attempts < max_attempts)
   {
      // Pick random source (input or node)
      int in_id = (int)(RandomRange(0, m_input_count + node_count - 0.001));
      
      // Pick random target (must be hidden or output node)
      int out_idx = (int)(RandomRange(0, node_count - 0.001));
      int out_id = m_nodes[out_idx].id;
      
      // Don't connect input to input
      if(out_id < m_input_count)
      {
         attempts++;
         continue;
      }
      
      // Check if link already exists
      if(!LinkExists(in_id, out_id))
      {
         // Create new link
         AddLink(in_id, out_id, RandomRange(-1.0, 1.0));
         return;
      }
      
      attempts++;
   }
}

//+------------------------------------------------------------------+
//| Mutate_PerturbWeights - Jitter weights with Gaussian noise       |
//+------------------------------------------------------------------+
void CNetwork::Mutate_PerturbWeights()
{
   int link_count = ArraySize(m_links);
   
   for(int i = 0; i < link_count; i++)
   {
      if(!m_links[i].enabled)
         continue;
      
      // Gaussian approximation: sum of uniform random variables
      double gauss = 0.0;
      for(int j = 0; j < 12; j++)
         gauss += RandomRange(0.0, 1.0);
      gauss = (gauss - 6.0) * 0.1;  // Mean=0, StdDev~0.1
      
      m_links[i].weight += gauss;
      
      // Clamp to reasonable range
      if(m_links[i].weight > 5.0)  m_links[i].weight = 5.0;
      if(m_links[i].weight < -5.0) m_links[i].weight = -5.0;
   }
}

//+------------------------------------------------------------------+
//| Sigmoid activation                                                |
//+------------------------------------------------------------------+
double CNetwork::Sigmoid(double x)
{
   // Clamp to prevent overflow
   if(x > 20.0)  return 1.0;
   if(x < -20.0) return 0.0;
   
   return 1.0 / (1.0 + MathExp(-x));
}

//+------------------------------------------------------------------+
//| Tanh activation                                                   |
//+------------------------------------------------------------------+
double CNetwork::Tanh(double x)
{
   // Clamp to prevent overflow
   if(x > 20.0)  return 1.0;
   if(x < -20.0) return -1.0;
   
   double exp_pos = MathExp(x);
   double exp_neg = MathExp(-x);
   
   return (exp_pos - exp_neg) / (exp_pos + exp_neg);
}

//+------------------------------------------------------------------+
//| Random value in range                                             |
//+------------------------------------------------------------------+
double CNetwork::RandomRange(double min, double max)
{
   return min + (max - min) * (MathRand() / 32767.0);
}

//+------------------------------------------------------------------+
//| Find node index by ID                                             |
//+------------------------------------------------------------------+
int CNetwork::FindNodeIndex(int node_id)
{
   int count = ArraySize(m_nodes);
   for(int i = 0; i < count; i++)
   {
      if(m_nodes[i].id == node_id)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Check if link exists                                              |
//+------------------------------------------------------------------+
bool CNetwork::LinkExists(int in_id, int out_id)
{
   int count = ArraySize(m_links);
   for(int i = 0; i < count; i++)
   {
      if(m_links[i].in_node_id == in_id && m_links[i].out_node_id == out_id)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Add node to network                                               |
//+------------------------------------------------------------------+
void CNetwork::AddNode(ENUM_NODE_TYPE type, ENUM_ACTIVATION act)
{
   int count = ArraySize(m_nodes);
   ArrayResize(m_nodes, count + 1);
   
   m_nodes[count].id = m_node_counter++;
   m_nodes[count].type = type;
   m_nodes[count].bias = 0.0;
   m_nodes[count].response = 1.0;
   m_nodes[count].activation = act;
   m_nodes[count].value = 0.0;
   m_nodes[count].sum = 0.0;
}

//+------------------------------------------------------------------+
//| Add link to network                                               |
//+------------------------------------------------------------------+
void CNetwork::AddLink(int in_id, int out_id, double weight)
{
   int count = ArraySize(m_links);
   ArrayResize(m_links, count + 1);
   
   m_links[count].in_node_id = in_id;
   m_links[count].out_node_id = out_id;
   m_links[count].weight = weight;
   m_links[count].enabled = true;
   m_links[count].recurrent = false;  // Could be enhanced to detect recurrent
}
//+------------------------------------------------------------------+
