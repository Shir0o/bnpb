import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';

/// Home page with a graph view of contacts
class HomePage extends StatelessWidget {
  HomePage({super.key});

  // Sample data for contacts
  final Map<String, List<String>> contactRelationships = {
    'John': ['Alice', 'Bob'],
    'Alice': ['Charlie'],
    'Bob': ['David', 'Eve'],
    'Charlie': [],
    'David': [],
    'Eve': [],
  };

  @override
  Widget build(BuildContext context) {
    // Create the graph
    final Graph graph = Graph()..isTree = true;
    final Map<String, Node> nodes = {};

    // Add nodes and edges
    contactRelationships.forEach((contact, relatedContacts) {
      nodes[contact] ??= Node.Id(contact);
      for (final related in relatedContacts) {
        nodes[related] ??= Node.Id(related);
        graph.addEdge(nodes[contact]!, nodes[related]!);
      }
    });

    final builder = BuchheimWalkerConfiguration()
      ..siblingSeparation = 100
      ..levelSeparation = 100
      ..subtreeSeparation = 100
      ..orientation = BuchheimWalkerConfiguration.ORIENTATION_TOP_BOTTOM;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Page'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Contacts Graph',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: InteractiveViewer(
                constrained: false,
                boundaryMargin: const EdgeInsets.all(100),
                minScale: 0.01,
                maxScale: 5.0,
                child: GraphView(
                  graph: graph,
                  algorithm: BuchheimWalkerAlgorithm(
                    builder,
                    TreeEdgeRenderer(builder),
                  ),
                  paint: Paint()
                    ..color = Colors.blue
                    ..strokeWidth = 2
                    ..style = PaintingStyle.stroke,
                  builder: (Node node) {
                    final String label = node.key!.value as String;
                    return _buildContactNode(label);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactNode(String contactName) {
    return GestureDetector(
      onTap: () {
        debugPrint('Tapped on $contactName');
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.lightBlueAccent,
        ),
        child: Text(
          contactName,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
