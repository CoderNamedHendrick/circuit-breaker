import 'package:flutter/material.dart';
import 'package:ferry_flutter/ferry_flutter.dart';
import 'package:frontend/src/circuit_editor/circuit_editor.dart';
import 'graphql_client.dart';
import 'src/graphql/__generated__/circuits.req.gql.dart';

class TestQueryPage extends StatefulWidget {
  const TestQueryPage({super.key});

  @override
  State<TestQueryPage> createState() => _TestQueryPageState();
}

class _TestQueryPageState extends State<TestQueryPage> {
  // Store the request in state to be able to recreate it
  late GGetCircuitsReq _getCircuitsRequest;

  @override
  void initState() {
    super.initState();
    _getCircuitsRequest = _createNewRequest();
  }

  GGetCircuitsReq _createNewRequest() {
    // For GGetCircuitsReq, there are no variables, so it's simple.
    // If it had variables that could change or you wanted to ensure
    // a cache bypass, you might add some cache-busting var here.
    return GGetCircuitsReq();
  }

  void _triggerRefresh() {
    setState(() {
      // Create a new instance of the request. This tells Ferry to re-execute.
      _getCircuitsRequest = _createNewRequest();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Refreshing circuits...'), duration: Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Circuit Test'),
        actions: [
          TextButton(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (context) => CircuitEditor()));
              _triggerRefresh();
            },
            child: Text("Create New Circuit"),
          ),
        ],
      ),
      body: Operation(
        client: client,
        operationRequest: _getCircuitsRequest,
        builder: (context, response, error) {
          if (response?.loading == true) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Connecting to GraphQL server...'),
                  Text('URL: http://localhost:8080/query'),
                ],
              ),
            );
          }

          if (error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, color: Colors.red, size: 48),
                  SizedBox(height: 16),
                  Text('Connection Error:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('$error', style: TextStyle(color: Colors.red)),
                ],
              ),
            );
          }

          if (response?.hasErrors == true) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 48),
                  SizedBox(height: 16),
                  Text('GraphQL Error:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(response?.graphqlErrors?.first.message ?? "Unknown error", style: TextStyle(color: Colors.red)),
                ],
              ),
            );
          }

          final data = response?.data;
          if (data?.circuits == null) {
            return Center(child: Text('No circuits found'));
          }

          final circuits = data!.circuits;
          if (circuits.isEmpty) {
            return Center(child: Text('No circuits available'));
          }

          return ListView.builder(
            itemCount: circuits.length,
            itemBuilder: (context, index) {
              final circuit = circuits[index];
              return Card(
                margin: EdgeInsets.all(8),
                child: ListTile(
                  onTap: () {
                    Navigator.of(
                      context,
                    ).push(MaterialPageRoute(builder: (context) => CircuitEditor(circuit: circuit)));
                    _triggerRefresh();
                  },
                  title: Text(circuit.title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ID: ${circuit.id}'),
                      Text('Nodes: ${circuit.nodes.length}'),
                      Text('Edges: ${circuit.edges.length}'),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
