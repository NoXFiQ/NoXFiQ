import 'package:flutter/material.dart';
import '../utils/constants.dart';

class SearchBarWidget extends StatefulWidget {
  final Function(String) onSearch;

  const SearchBarWidget({
    super.key,
    required this.onSearch,
  });

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: 'Tafuta bidhaa...',
          hintStyle: TextStyle(color: AppColors.textSecondary),
          prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: AppColors.textSecondary),
                  onPressed: () {
                    _controller.clear();
                    widget.onSearch('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
        onChanged: widget.onSearch,
        onSubmitted: widget.onSearch,
      ),
    );
  }
}