//+------------------------------------------------------------------+
//|                                                     CNetwork.mqh |
//|                                        MQL5 Neural Network Class |
//|                                       Standalone, No Dependencies |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Node types                                                        |
//+------------------------------------------------------------------+
enum ENUM_NODE_TYPE
{
   NODE_INPUT,      // Input node
   NODE_HIDDEN,     // Hidden node
   NODE_OUTPUT,     // Output node (5 fixed: Buy, Sell, Filter, SL, TP)
   NODE_RECURRENT   // Recurrent node for memory
};

//+------------------------------------------------------------------+
//| Output node indices (5 fixed outputs)                            |
//+------------------------------------------------------------------+
enum ENUM_OUTPUT_NODE
{
   OUT_BUY = 0,     // Buy signal
   OUT_SELL = 1,    // Sell signal
   OUT_FILTER = 2,  // Filter signal
   OUT_SL = 3,      // Stop Loss
   OUT_TP = 4       // Take Profit
};

//+------------------------------------------------------------------+
//| Node structure                                                    |
//+------------------------------------------------------------------+
struct SNode
{
   int               id;              // Unique node ID
   ENUM_NODE_TYPE    type;            // Node type
   double            value;           // Current activation value
   double            recurrentBuffer; // Buffer for recurrent connections
   int               topoLevel;       // Topological level for sorting
   
   void Init(int nodeId, ENUM_NODE_TYPE nodeType)
   {
      id = nodeId;
      type = nodeType;
      value = 0.0;
      recurrentBuffer = 0.0;
      topoLevel = 0;
   }
};

//+------------------------------------------------------------------+
//| Connection (Gene) structure                                       |
//+------------------------------------------------------------------+
struct SConnection
{
   int               fromNode;        // Source node ID
   int               toNode;          // Target node ID
   double            weight;          // Connection weight
   bool              enabled;         // Connection enabled flag
   bool              frozen;          // Frozen flag (for mutation)
   bool              recurrent;       // Is this a recurrent connection
   int               innovation;      // Innovation number (for sorting)
   
   void Init(int from, int to, double w, int innov)
   {
      fromNode = from;
      toNode = to;
      weight = w;
      enabled = true;
      frozen = false;
      recurrent = false;
      innovation = innov;
   }
};

//+------------------------------------------------------------------+
//| CNetwork class - Standalone neural network                       |
//+------------------------------------------------------------------+
class CNetwork
{
private:
   // Node management
   SNode             m_nodes[];           // All nodes in network
   int               m_nodeCount;         // Current number of nodes
   int               m_nextNodeId;        // Next available node ID
   
   // Connection management
   SConnection       m_connections[];     // All connections (genes)
   int               m_connectionCount;   // Current number of connections
   int               m_nextInnovation;    // Next innovation number
   
   // Network structure
   int               m_inputCount;        // Number of input nodes
   int               m_outputCount;       // Fixed at 5
   int               m_hiddenCount;       // Number of hidden nodes
   
   // Execution order
   int               m_execOrder[];       // Node execution order (topological sort)
   int               m_execOrderSize;     // Size of execution order
   
   // Helper methods
   int               FindNodeIndex(int nodeId);
   void              CalculateTopologicalOrder();
   double            Activate(double x);
   double            Sigmoid(double x);
   void              SortConnectionsByInnovation();
   void              UpdateTopologicalLevels();
   
   // CSV persistence helpers
   bool              SaveToCSV(const string filename);
   bool              LoadFromCSV(const string filename);
   string            NodeTypeToString(ENUM_NODE_TYPE type);
   ENUM_NODE_TYPE    StringToNodeType(const string str);
   
public:
                     CNetwork();
                    ~CNetwork();
   
   // Initialization
   bool              Initialize(int inputCount);
   void              Reset();
   
   // Forward pass
   bool              FeedForward(const double &inputs[]);
   bool              GetOutputs(double &outputs[]);
   double            GetOutput(ENUM_OUTPUT_NODE outputNode);
   
   // Mutation operations
   bool              MutateLateral();      // Add new input->hidden->output
   bool              MutateMemory();       // Add recurrent connection
   bool              MutateDepth();        // Split existing connection
   
   // State management
   void              ResetRecurrentBuffers();
   
   // Persistence
   bool              SaveToFile(const string filename, bool asCSV = false);
   bool              LoadFromFile(const string filename);
   
   // Getters
   int               GetInputCount() const { return m_inputCount; }
   int               GetOutputCount() const { return m_outputCount; }
   int               GetNodeCount() const { return m_nodeCount; }
   int               GetConnectionCount() const { return m_connectionCount; }
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CNetwork::CNetwork()
{
   m_nodeCount = 0;
   m_nextNodeId = 0;
   m_connectionCount = 0;
   m_nextInnovation = 0;
   m_inputCount = 0;
   m_outputCount = 5; // Fixed
   m_hiddenCount = 0;
   m_execOrderSize = 0;
   
   ArrayResize(m_nodes, 0);
   ArrayResize(m_connections, 0);
   ArrayResize(m_execOrder, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CNetwork::~CNetwork()
{
   ArrayFree(m_nodes);
   ArrayFree(m_connections);
   ArrayFree(m_execOrder);
}

//+------------------------------------------------------------------+
//| Initialize network with dynamic inputs and 5 fixed outputs       |
//+------------------------------------------------------------------+
bool CNetwork::Initialize(int inputCount)
{
   if(inputCount <= 0)
      return false;
   
   Reset();
   
   m_inputCount = inputCount;
   m_nodeCount = inputCount + m_outputCount;
   
   ArrayResize(m_nodes, m_nodeCount);
   
   // Create input nodes
   for(int i = 0; i < m_inputCount; i++)
   {
      m_nodes[i].Init(m_nextNodeId++, NODE_INPUT);
   }
   
   // Create output nodes (5 fixed)
   for(int i = 0; i < m_outputCount; i++)
   {
      m_nodes[m_inputCount + i].Init(m_nextNodeId++, NODE_OUTPUT);
   }
   
   // Initial connections: all inputs to all outputs with random weights
   int expectedConnections = m_inputCount * m_outputCount;
   ArrayResize(m_connections, expectedConnections);
   
   m_connectionCount = 0;
   for(int i = 0; i < m_inputCount; i++)
   {
      for(int j = 0; j < m_outputCount; j++)
      {
         int fromId = m_nodes[i].id;
         int toId = m_nodes[m_inputCount + j].id;
         double weight = (MathRand() / 32767.0) * 2.0 - 1.0; // Random [-1, 1]
         
         m_connections[m_connectionCount].Init(fromId, toId, weight, m_nextInnovation++);
         m_connectionCount++;
      }
   }
   
   SortConnectionsByInnovation();
   CalculateTopologicalOrder();
   
   return true;
}

//+------------------------------------------------------------------+
//| Reset network state                                               |
//+------------------------------------------------------------------+
void CNetwork::Reset()
{
   m_nodeCount = 0;
   m_nextNodeId = 0;
   m_connectionCount = 0;
   m_nextInnovation = 0;
   m_inputCount = 0;
   m_hiddenCount = 0;
   m_execOrderSize = 0;
   
   ArrayResize(m_nodes, 0);
   ArrayResize(m_connections, 0);
   ArrayResize(m_execOrder, 0);
}

//+------------------------------------------------------------------+
//| Find node index by ID                                             |
//+------------------------------------------------------------------+
int CNetwork::FindNodeIndex(int nodeId)
{
   for(int i = 0; i < m_nodeCount; i++)
   {
      if(m_nodes[i].id == nodeId)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Activation function (tanh) for hidden nodes                      |
//+------------------------------------------------------------------+
double CNetwork::Activate(double x)
{
   return MathTanh(x);
}

//+------------------------------------------------------------------+
//| Sigmoid activation function for output nodes                     |
//+------------------------------------------------------------------+
double CNetwork::Sigmoid(double x)
{
   return 1.0 / (1.0 + MathExp(-x));
}

//+------------------------------------------------------------------+
//| Sort connections by innovation number                             |
//+------------------------------------------------------------------+
void CNetwork::SortConnectionsByInnovation()
{
   // Simple bubble sort (sufficient for neural network sizes)
   for(int i = 0; i < m_connectionCount - 1; i++)
   {
      for(int j = 0; j < m_connectionCount - i - 1; j++)
      {
         if(m_connections[j].innovation > m_connections[j + 1].innovation)
         {
            // Swap
            SConnection temp = m_connections[j];
            m_connections[j] = m_connections[j + 1];
            m_connections[j + 1] = temp;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update topological levels for all nodes                          |
//+------------------------------------------------------------------+
void CNetwork::UpdateTopologicalLevels()
{
   // Reset all levels
   for(int i = 0; i < m_nodeCount; i++)
   {
      if(m_nodes[i].type == NODE_INPUT)
         m_nodes[i].topoLevel = 0;
      else
         m_nodes[i].topoLevel = -1;
   }
   
   // Iteratively propagate levels (skip recurrent connections)
   bool changed = true;
   int maxIterations = m_nodeCount * 2;
   int iteration = 0;
   
   while(changed && iteration < maxIterations)
   {
      changed = false;
      iteration++;
      
      for(int c = 0; c < m_connectionCount; c++)
      {
         if(!m_connections[c].enabled || m_connections[c].recurrent)
            continue;
         
         int fromIdx = FindNodeIndex(m_connections[c].fromNode);
         int toIdx = FindNodeIndex(m_connections[c].toNode);
         
         if(fromIdx < 0 || toIdx < 0)
            continue;
         
         if(m_nodes[fromIdx].topoLevel >= 0)
         {
            int newLevel = m_nodes[fromIdx].topoLevel + 1;
            if(m_nodes[toIdx].topoLevel < newLevel)
            {
               m_nodes[toIdx].topoLevel = newLevel;
               changed = true;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate topological execution order                            |
//+------------------------------------------------------------------+
void CNetwork::CalculateTopologicalOrder()
{
   UpdateTopologicalLevels();
   
   // Create execution order (skip input nodes, they're just set)
   int execNodes = m_nodeCount - m_inputCount;
   ArrayResize(m_execOrder, execNodes);
   m_execOrderSize = 0;
   
   // Collect non-input nodes
   for(int i = 0; i < m_nodeCount; i++)
   {
      if(m_nodes[i].type != NODE_INPUT)
      {
         m_execOrder[m_execOrderSize++] = i;
      }
   }
   
   // Sort by topological level
   for(int i = 0; i < m_execOrderSize - 1; i++)
   {
      for(int j = 0; j < m_execOrderSize - i - 1; j++)
      {
         if(m_nodes[m_execOrder[j]].topoLevel > m_nodes[m_execOrder[j + 1]].topoLevel)
         {
            int temp = m_execOrder[j];
            m_execOrder[j] = m_execOrder[j + 1];
            m_execOrder[j + 1] = temp;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Feed forward execution (topologically sorted)                    |
//+------------------------------------------------------------------+
bool CNetwork::FeedForward(const double &inputs[])
{
   if(ArraySize(inputs) != m_inputCount)
      return false;
   
   // Set input values
   for(int i = 0; i < m_inputCount; i++)
   {
      m_nodes[i].value = inputs[i];
   }
   
   // Reset non-input node values
   for(int i = m_inputCount; i < m_nodeCount; i++)
   {
      m_nodes[i].value = 0.0;
   }
   
   // Execute in topological order
   for(int e = 0; e < m_execOrderSize; e++)
   {
      int nodeIdx = m_execOrder[e];
      int nodeId = m_nodes[nodeIdx].id;
      double sum = 0.0;
      
      // Sum all incoming connections
      for(int c = 0; c < m_connectionCount; c++)
      {
         if(!m_connections[c].enabled)
            continue;
         
         if(m_connections[c].toNode == nodeId)
         {
            int fromIdx = FindNodeIndex(m_connections[c].fromNode);
            if(fromIdx >= 0)
            {
               double inputVal;
               
               // Handle recurrent connections
               if(m_connections[c].recurrent)
               {
                  inputVal = m_nodes[fromIdx].recurrentBuffer;
               }
               else
               {
                  inputVal = m_nodes[fromIdx].value;
               }
               
               sum += inputVal * m_connections[c].weight;
            }
         }
      }
      
      // Apply activation based on node type
      if(m_nodes[nodeIdx].type == NODE_OUTPUT)
      {
         // Output nodes use Sigmoid [0, 1]
         m_nodes[nodeIdx].value = Sigmoid(sum);
         
         // Assert output is non-negative (Sigmoid guarantees this)
         if(m_nodes[nodeIdx].value < 0.0)
            m_nodes[nodeIdx].value = 0.0;
      }
      else
      {
         // Hidden/Recurrent nodes use Tanh [-1, 1]
         m_nodes[nodeIdx].value = Activate(sum);
      }
      
      // Update recurrent buffer for next iteration
      m_nodes[nodeIdx].recurrentBuffer = m_nodes[nodeIdx].value;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get all output values                                             |
//+------------------------------------------------------------------+
bool CNetwork::GetOutputs(double &outputs[])
{
   ArrayResize(outputs, m_outputCount);
   
   for(int i = 0; i < m_outputCount; i++)
   {
      int outputIdx = m_inputCount + i;
      if(outputIdx < m_nodeCount)
         outputs[i] = m_nodes[outputIdx].value;
      else
         outputs[i] = 0.0;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get specific output value                                         |
//+------------------------------------------------------------------+
double CNetwork::GetOutput(ENUM_OUTPUT_NODE outputNode)
{
   int outputIdx = m_inputCount + (int)outputNode;
   if(outputIdx >= 0 && outputIdx < m_nodeCount)
      return m_nodes[outputIdx].value;
   return 0.0;
}

//+------------------------------------------------------------------+
//| Lateral mutation: New Input -> New Hidden -> Output              |
//| Adds new input and hidden node, connects to output with w=0      |
//| Freezes old connections                                           |
//+------------------------------------------------------------------+
bool CNetwork::MutateLateral()
{
   // Freeze all existing connections
   for(int i = 0; i < m_connectionCount; i++)
   {
      m_connections[i].frozen = true;
   }
   
   // Add new input node
   ArrayResize(m_nodes, m_nodeCount + 2);
   m_nodes[m_nodeCount].Init(m_nextNodeId++, NODE_INPUT);
   m_inputCount++;
   int newInputIdx = m_nodeCount;
   m_nodeCount++;
   
   // Add new hidden node
   m_nodes[m_nodeCount].Init(m_nextNodeId++, NODE_HIDDEN);
   m_hiddenCount++;
   int newHiddenIdx = m_nodeCount;
   m_nodeCount++;
   
   // Add connections: NewInput -> NewHidden -> Random Output (weight = 0)
   int randomOutput = m_inputCount + (MathRand() % m_outputCount);
   
   ArrayResize(m_connections, m_connectionCount + 2);
   
   // NewInput -> NewHidden
   m_connections[m_connectionCount].Init(m_nodes[newInputIdx].id, 
                                          m_nodes[newHiddenIdx].id, 
                                          0.0, 
                                          m_nextInnovation++);
   m_connectionCount++;
   
   // NewHidden -> Output
   m_connections[m_connectionCount].Init(m_nodes[newHiddenIdx].id, 
                                          m_nodes[randomOutput].id, 
                                          0.0, 
                                          m_nextInnovation++);
   m_connectionCount++;
   
   SortConnectionsByInnovation();
   CalculateTopologicalOrder();
   
   return true;
}

//+------------------------------------------------------------------+
//| Memory mutation: Add recurrent node -> output                    |
//| Creates recurrent connection with w=0, freezes old connections   |
//+------------------------------------------------------------------+
bool CNetwork::MutateMemory()
{
   // Freeze all existing connections
   for(int i = 0; i < m_connectionCount; i++)
   {
      m_connections[i].frozen = true;
   }
   
   // Add new recurrent hidden node
   ArrayResize(m_nodes, m_nodeCount + 1);
   m_nodes[m_nodeCount].Init(m_nextNodeId++, NODE_RECURRENT);
   m_hiddenCount++;
   int newRecurrentIdx = m_nodeCount;
   m_nodeCount++;
   
   // Create self-recurrent connection
   ArrayResize(m_connections, m_connectionCount + 2);
   
   m_connections[m_connectionCount].Init(m_nodes[newRecurrentIdx].id,
                                          m_nodes[newRecurrentIdx].id,
                                          0.0,
                                          m_nextInnovation++);
   m_connections[m_connectionCount].recurrent = true;
   m_connectionCount++;
   
   // Connect to random output
   int randomOutput = m_inputCount + (MathRand() % m_outputCount);
   m_connections[m_connectionCount].Init(m_nodes[newRecurrentIdx].id,
                                          m_nodes[randomOutput].id,
                                          0.0,
                                          m_nextInnovation++);
   m_connectionCount++;
   
   SortConnectionsByInnovation();
   CalculateTopologicalOrder();
   
   return true;
}

//+------------------------------------------------------------------+
//| Depth mutation: Split connection A->B into A->New->B             |
//| A->New has weight=1.0, New->B has old weight, no freeze          |
//+------------------------------------------------------------------+
bool CNetwork::MutateDepth()
{
   if(m_connectionCount == 0)
      return false;
   
   // Find a random enabled non-recurrent connection to split
   int attempts = 0;
   int maxAttempts = m_connectionCount * 2;
   int connIdx = -1;
   
   while(attempts < maxAttempts)
   {
      connIdx = MathRand() % m_connectionCount;
      if(m_connections[connIdx].enabled && !m_connections[connIdx].recurrent)
         break;
      attempts++;
   }
   
   if(connIdx < 0 || !m_connections[connIdx].enabled || m_connections[connIdx].recurrent)
      return false;
   
   // Disable original connection
   m_connections[connIdx].enabled = false;
   
   int fromNode = m_connections[connIdx].fromNode;
   int toNode = m_connections[connIdx].toNode;
   double oldWeight = m_connections[connIdx].weight;
   
   // Add new hidden node
   ArrayResize(m_nodes, m_nodeCount + 1);
   m_nodes[m_nodeCount].Init(m_nextNodeId++, NODE_HIDDEN);
   m_hiddenCount++;
   int newHiddenIdx = m_nodeCount;
   m_nodeCount++;
   
   // Add two new connections
   ArrayResize(m_connections, m_connectionCount + 2);
   
   // From -> New (weight = 1.0)
   m_connections[m_connectionCount].Init(fromNode,
                                          m_nodes[newHiddenIdx].id,
                                          1.0,
                                          m_nextInnovation++);
   m_connectionCount++;
   
   // New -> To (old weight)
   m_connections[m_connectionCount].Init(m_nodes[newHiddenIdx].id,
                                          toNode,
                                          oldWeight,
                                          m_nextInnovation++);
   m_connectionCount++;
   
   SortConnectionsByInnovation();
   CalculateTopologicalOrder();
   
   return true;
}

//+------------------------------------------------------------------+
//| Reset all recurrent buffers to 0                                 |
//+------------------------------------------------------------------+
void CNetwork::ResetRecurrentBuffers()
{
   for(int i = 0; i < m_nodeCount; i++)
   {
      m_nodes[i].recurrentBuffer = 0.0;
   }
}

//+------------------------------------------------------------------+
//| Save network topology and weights to file (skip buffers)         |
//+------------------------------------------------------------------+
bool CNetwork::SaveToFile(const string filename, bool asCSV = false)
{
   // If CSV format requested, use CSV export
   if(asCSV)
      return SaveToCSV(filename);
   
   // Binary format
   int handle = FileOpen(filename, FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return false;
   
   // Write header
   FileWriteInteger(handle, m_inputCount);
   FileWriteInteger(handle, m_outputCount);
   FileWriteInteger(handle, m_nodeCount);
   FileWriteInteger(handle, m_connectionCount);
   FileWriteInteger(handle, m_nextNodeId);
   FileWriteInteger(handle, m_nextInnovation);
   
   // Write nodes (skip recurrent buffer)
   for(int i = 0; i < m_nodeCount; i++)
   {
      FileWriteInteger(handle, m_nodes[i].id);
      FileWriteInteger(handle, (int)m_nodes[i].type);
      FileWriteInteger(handle, m_nodes[i].topoLevel);
   }
   
   // Write connections
   for(int i = 0; i < m_connectionCount; i++)
   {
      FileWriteInteger(handle, m_connections[i].fromNode);
      FileWriteInteger(handle, m_connections[i].toNode);
      FileWriteDouble(handle, m_connections[i].weight);
      FileWriteInteger(handle, m_connections[i].enabled ? 1 : 0);
      FileWriteInteger(handle, m_connections[i].frozen ? 1 : 0);
      FileWriteInteger(handle, m_connections[i].recurrent ? 1 : 0);
      FileWriteInteger(handle, m_connections[i].innovation);
   }
   
   FileClose(handle);
   return true;
}

//+------------------------------------------------------------------+
//| Load network topology and weights from file                      |
//+------------------------------------------------------------------+
bool CNetwork::LoadFromFile(const string filename)
{
   // Check if file is CSV based on extension
   string ext = "";
   int dot_pos = StringFind(filename, ".", 0);
   if(dot_pos >= 0)
   {
      ext = StringSubstr(filename, dot_pos + 1);
      StringToUpper(ext);
   }
   
   if(ext == "CSV")
      return LoadFromCSV(filename);
   
   // Binary format
   int handle = FileOpen(filename, FILE_READ | FILE_BIN | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return false;
   
   Reset();
   
   // Read header
   m_inputCount = FileReadInteger(handle);
   m_outputCount = FileReadInteger(handle);
   m_nodeCount = FileReadInteger(handle);
   m_connectionCount = FileReadInteger(handle);
   m_nextNodeId = FileReadInteger(handle);
   m_nextInnovation = FileReadInteger(handle);
   
   // Read nodes
   ArrayResize(m_nodes, m_nodeCount);
   for(int i = 0; i < m_nodeCount; i++)
   {
      m_nodes[i].id = FileReadInteger(handle);
      m_nodes[i].type = (ENUM_NODE_TYPE)FileReadInteger(handle);
      m_nodes[i].topoLevel = FileReadInteger(handle);
      m_nodes[i].value = 0.0;
      m_nodes[i].recurrentBuffer = 0.0; // Always initialize to 0
   }
   
   // Calculate hidden count
   m_hiddenCount = 0;
   for(int i = 0; i < m_nodeCount; i++)
   {
      if(m_nodes[i].type == NODE_HIDDEN || m_nodes[i].type == NODE_RECURRENT)
         m_hiddenCount++;
   }
   
   // Read connections
   ArrayResize(m_connections, m_connectionCount);
   for(int i = 0; i < m_connectionCount; i++)
   {
      m_connections[i].fromNode = FileReadInteger(handle);
      m_connections[i].toNode = FileReadInteger(handle);
      m_connections[i].weight = FileReadDouble(handle);
      m_connections[i].enabled = (FileReadInteger(handle) != 0);
      m_connections[i].frozen = (FileReadInteger(handle) != 0);
      m_connections[i].recurrent = (FileReadInteger(handle) != 0);
      m_connections[i].innovation = FileReadInteger(handle);
   }
   
   FileClose(handle);
   
   SortConnectionsByInnovation();
   CalculateTopologicalOrder();
   
   return true;
}

//+------------------------------------------------------------------+
//| Convert node type enum to string                                 |
//+------------------------------------------------------------------+
string CNetwork::NodeTypeToString(ENUM_NODE_TYPE type)
{
   switch(type)
   {
      case NODE_INPUT:     return "INPUT";
      case NODE_HIDDEN:    return "HIDDEN";
      case NODE_OUTPUT:    return "OUTPUT";
      case NODE_RECURRENT: return "RECURRENT";
      default:             return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| Convert string to node type enum                                 |
//+------------------------------------------------------------------+
ENUM_NODE_TYPE CNetwork::StringToNodeType(const string str)
{
   if(str == "INPUT")     return NODE_INPUT;
   if(str == "HIDDEN")    return NODE_HIDDEN;
   if(str == "OUTPUT")    return NODE_OUTPUT;
   if(str == "RECURRENT") return NODE_RECURRENT;
   return NODE_INPUT; // Default
}

//+------------------------------------------------------------------+
//| Save network to CSV format for inspection                        |
//+------------------------------------------------------------------+
bool CNetwork::SaveToCSV(const string filename)
{
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
      return false;
   
   // Write network metadata section
   FileWrite(handle, "# NETWORK METADATA");
   FileWrite(handle, "InputCount", m_inputCount);
   FileWrite(handle, "OutputCount", m_outputCount);
   FileWrite(handle, "NodeCount", m_nodeCount);
   FileWrite(handle, "ConnectionCount", m_connectionCount);
   FileWrite(handle, "NextNodeId", m_nextNodeId);
   FileWrite(handle, "NextInnovation", m_nextInnovation);
   FileWrite(handle, "");
   
   // Write nodes section
   FileWrite(handle, "# NODES");
   FileWrite(handle, "NodeID", "Type", "TopoLevel");
   for(int i = 0; i < m_nodeCount; i++)
   {
      FileWrite(handle, 
                m_nodes[i].id,
                NodeTypeToString(m_nodes[i].type),
                m_nodes[i].topoLevel);
   }
   FileWrite(handle, "");
   
   // Write connections section
   FileWrite(handle, "# CONNECTIONS");
   FileWrite(handle, "Innovation", "From", "To", "Weight", "Enabled", "Frozen", "Recurrent");
   for(int i = 0; i < m_connectionCount; i++)
   {
      FileWrite(handle,
                m_connections[i].innovation,
                m_connections[i].fromNode,
                m_connections[i].toNode,
                DoubleToString(m_connections[i].weight, 8),
                m_connections[i].enabled ? "TRUE" : "FALSE",
                m_connections[i].frozen ? "TRUE" : "FALSE",
                m_connections[i].recurrent ? "TRUE" : "FALSE");
   }
   
   FileClose(handle);
   return true;
}

//+------------------------------------------------------------------+
//| Load network from CSV format                                     |
//+------------------------------------------------------------------+
bool CNetwork::LoadFromCSV(const string filename)
{
   int handle = FileOpen(filename, FILE_READ | FILE_CSV | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
      return false;
   
   Reset();
   
   // Read metadata section
   string line;
   while(!FileIsEnding(handle))
   {
      line = FileReadString(handle);
      if(StringFind(line, "# NETWORK METADATA") >= 0) break;
   }
   
   // Read metadata values
   FileReadString(handle); m_inputCount = (int)FileReadNumber(handle);
   FileReadString(handle); m_outputCount = (int)FileReadNumber(handle);
   FileReadString(handle); m_nodeCount = (int)FileReadNumber(handle);
   FileReadString(handle); m_connectionCount = (int)FileReadNumber(handle);
   FileReadString(handle); m_nextNodeId = (int)FileReadNumber(handle);
   FileReadString(handle); m_nextInnovation = (int)FileReadNumber(handle);
   
   // Skip to nodes section
   while(!FileIsEnding(handle))
   {
      line = FileReadString(handle);
      if(StringFind(line, "# NODES") >= 0) break;
   }
   
   // Skip header line
   FileReadString(handle);
   
   // Read nodes
   ArrayResize(m_nodes, m_nodeCount);
   for(int i = 0; i < m_nodeCount; i++)
   {
      m_nodes[i].id = (int)FileReadNumber(handle);
      m_nodes[i].type = StringToNodeType(FileReadString(handle));
      m_nodes[i].topoLevel = (int)FileReadNumber(handle);
      m_nodes[i].value = 0.0;
      m_nodes[i].recurrentBuffer = 0.0;
   }
   
   // Calculate hidden count
   m_hiddenCount = 0;
   for(int i = 0; i < m_nodeCount; i++)
   {
      if(m_nodes[i].type == NODE_HIDDEN || m_nodes[i].type == NODE_RECURRENT)
         m_hiddenCount++;
   }
   
   // Skip to connections section
   while(!FileIsEnding(handle))
   {
      line = FileReadString(handle);
      if(StringFind(line, "# CONNECTIONS") >= 0) break;
   }
   
   // Skip header line
   FileReadString(handle);
   
   // Read connections
   ArrayResize(m_connections, m_connectionCount);
   for(int i = 0; i < m_connectionCount; i++)
   {
      m_connections[i].innovation = (int)FileReadNumber(handle);
      m_connections[i].fromNode = (int)FileReadNumber(handle);
      m_connections[i].toNode = (int)FileReadNumber(handle);
      m_connections[i].weight = StringToDouble(FileReadString(handle));
      m_connections[i].enabled = (FileReadString(handle) == "TRUE");
      m_connections[i].frozen = (FileReadString(handle) == "TRUE");
      m_connections[i].recurrent = (FileReadString(handle) == "TRUE");
   }
   
   FileClose(handle);
   
   SortConnectionsByInnovation();
   CalculateTopologicalOrder();
   
   return true;
}

//+------------------------------------------------------------------+
